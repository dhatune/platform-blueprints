variable "prefix" {
  description = "Short organisation prefix."
  type        = string
}

variable "workload" {
  description = "Short workload identifier."
  type        = string
}

variable "location" {
  description = "Azure region. No default: choosing a region has data residency consequences."
  type        = string
}

variable "location_short" {
  description = "Abbreviated region used in names."
  type        = string
}

variable "subscription_id" {
  description = "Subscription everything is created in."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant that owns the key vault."
  type        = string
}

variable "hub_address_space" {
  description = "Address space of the hub network."
  type        = list(string)
  default     = ["10.60.0.0/22"]
}

variable "spoke_address_space" {
  description = "Address space of the spoke network. Must not overlap the hub."
  type        = list(string)
  default     = ["10.61.0.0/22"]

  # Overlapping ranges make the peering unusable, and the failure reads as a
  # routing problem rather than an addressing one. Comparing the two strings
  # for inequality does not catch it: a spoke nested inside the hub has a
  # different string and overlaps completely, so the check converts both to
  # numeric intervals.
  #
  # This lives in the configuration rather than only in the test suite on
  # purpose. A guard that fires only under `terraform test` leaves a direct
  # apply with an overlapping tfvars succeeding in silence.
  #
  # Each base is taken with cidrhost(cidr, 0), not split("/", cidr)[0]: the
  # latter takes the address exactly as written, so a non-canonical CIDR such
  # as "10.60.4.0/16" reads its base as "10.60.4.0" instead of the real network
  # base "10.60.0.0", and a space that does overlap plans clean.
  validation {
    condition = !(
      sum([for i, o in split(".", cidrhost(var.hub_address_space[0], 0)) : tonumber(o) * pow(256, 3 - i)]) < sum([for i, o in split(".", cidrhost(var.spoke_address_space[0], 0)) : tonumber(o) * pow(256, 3 - i)]) + pow(2, 32 - tonumber(split("/", var.spoke_address_space[0])[1]))
      && sum([for i, o in split(".", cidrhost(var.spoke_address_space[0], 0)) : tonumber(o) * pow(256, 3 - i)]) < sum([for i, o in split(".", cidrhost(var.hub_address_space[0], 0)) : tonumber(o) * pow(256, 3 - i)]) + pow(2, 32 - tonumber(split("/", var.hub_address_space[0])[1]))
    )
    error_message = "The hub and spoke address spaces overlap. The peering between them would be unusable, and the failure would read as a routing problem rather than an addressing one."
  }
}

variable "firewall_private_ip" {
  description = <<-EOT
    Address egress is routed to. Azure reserves the first four addresses of every
    subnet, so a firewall placed in 10.60.0.0/24 answers on 10.60.0.4.
  EOT
  type        = string
  default     = "10.60.0.4"
}

variable "subnets" {
  description = "Zones of the spoke. The keys name the zone, never the product that lives in it. Only zones something in this landing zone actually attaches to are declared: a reserved-but-idle zone is a range nothing can ever hold accountable."
  type = map(object({
    address_prefix                    = string
    private_endpoint_network_policies = optional(string, "Enabled")
    service_endpoints                 = optional(list(string), [])
  }))

  default = {
    cluster = { address_prefix = "10.61.1.0/24" }

    # Enabled, not Disabled: with network policies enabled, the subnet's
    # network security group and any application security group an endpoint
    # here joins are actually evaluated against traffic to and from it,
    # rather than bypassed.
    endpoints = { address_prefix = "10.61.2.0/27", private_endpoint_network_policies = "Enabled" }
  }
}

variable "allow_rules" {
  description = <<-EOT
    Explicit exceptions to the spoke's default deny, passed straight through to
    modules/network-spoke. main.tf adds one more entry of its own on top of
    this default: the cluster subnet reaching the application security group
    the vault and registry private endpoints join, which cannot be expressed
    here because a variable default cannot reference a resource that does not
    exist until this stack applies.

    This default covers the rest: the cluster subnet reaching itself on every
    protocol and port, the load balancer's health probe, and translated
    ingress arriving from the firewall subnet.

    A variable default cannot reference another variable, so the address
    prefixes below are var.subnets["cluster"].address_prefix written out by
    hand. If that subnet range changes, this default must move with it.
  EOT

  type = map(object({
    subnet_key            = string
    priority              = number
    direction             = string
    protocol              = string
    source_address_prefix = string
    description           = string

    destination_address_prefix                 = optional(string)
    destination_application_security_group_ids = optional(list(string))

    # Exactly one of these, mirroring modules/network-spoke.
    destination_port_range  = optional(string)
    destination_port_ranges = optional(list(string))
  }))

  default = {
    # A multi-node cluster needs far more between its own nodes than 443:
    # kubelet, kube-proxy, CNI and Cilium's own inter-node ports (health
    # checks, VXLAN, WireGuard depending on configuration), none of which is
    # a fixed, published list the way AzureKubernetesService's FQDN tag is.
    # Narrowing this to a single port is how a cluster with more than one
    # node stops working the moment a second node joins.
    #
    cluster_to_cluster_all = {
      subnet_key                 = "cluster"
      priority                   = 210
      direction                  = "Inbound"
      protocol                   = "*"
      source_address_prefix      = "10.61.1.0/24"
      destination_address_prefix = "10.61.1.0/24"
      destination_port_range     = "*"
      description                = "A multi-node cluster needs many ports between its own nodes, not only 443."
    }

    # The load balancer's health probe comes from the platform's own host
    # address, and the Azure default rule that admits it sits at 65001 --
    # below the deny at 4000, so it is never reached. That address is inside
    # the VirtualNetwork service tag, which is what the deny matches on, so
    # the deny swallows it.
    #
    # Without this rule an internal load balancer comes up, reports no healthy
    # backend, and drops every connection. Nothing appears in the firewall
    # logs, because a probe from the host address to a node never leaves the
    # subnet; only the VNet flow logs show it.
    loadbalancer_probe_to_cluster = {
      subnet_key                 = "cluster"
      priority                   = 205
      direction                  = "Inbound"
      protocol                   = "*"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "10.61.1.0/24"
      destination_port_range     = "*"
      description                = "Health probes of the internal load balancer. The Azure default that allows these sits below the deny at 4000 and is never evaluated."
    }

    # Ingress reaching the cluster after the firewall's translation.
    #
    # Azure Firewall translates BOTH the destination and the source address
    # on an inbound DNAT rule, which is documented behaviour and which check 9
    # reproduces: the ingress controller logs an address of the firewall's own
    # subnet as the caller. A rule admitting traffic from the internet
    # directly would never match anything. Two consequences follow, and the
    # second one matters more than this rule does:
    #
    #   - the perimeter is narrower than it looked: the cluster subnet accepts
    #     this traffic only from the hub, never from an arbitrary source;
    #
    #   - THE CLIENT ADDRESS IS LOST. Nothing behind this path can see who
    #     called: not rate limiting by client, not geographic rules, not an
    #     access log worth reading for abuse. Anything needing the caller's
    #     address must get it from a header set further out -- which means
    #     something further out has to exist. Setting externalTrafficPolicy
    #     to Local on the service, which preserves the source address through
    #     the load balancer, buys nothing here: the address was already gone
    #     one hop earlier.
    firewall_to_cluster_ingress = {
      subnet_key                 = "cluster"
      priority                   = 215
      direction                  = "Inbound"
      protocol                   = "Tcp"
      source_address_prefix      = "10.60.0.0/24"
      destination_address_prefix = "10.61.1.0/24"
      destination_port_ranges    = ["80", "443"]
      description                = "Translated ingress. Arrives from the firewall subnet: the firewall rewrites the source address as well as the destination."
    }
  }
}

variable "private_dns_zone_names" {
  description = <<-EOT
    Private DNS zones required by the managed services this landing zone fronts.
    The names are dictated by Azure and cannot be chosen.
  EOT
  type        = list(string)

  default = [
    "privatelink.blob.core.windows.net",
    "privatelink.vaultcore.azure.net",
    "privatelink.azurecr.io",
  ]
}

variable "storage_replication_type" {
  description = "Redundancy of the object repository. The laboratory runs without redundancy on purpose."
  type        = string
  default     = "LRS"
}

variable "vault_operator_ip_rules" {
  description = <<-EOT
    Addresses permitted to reach the vault's data plane from outside the
    network. Empty by default, which keeps the vault closed.

    The laboratory profile sets this to the operator's own address, because
    Terraform runs from that machine and writes one secret. The alternative is
    a private endpoint plus a runner inside the network, which is correct for
    production and costs the last vCPU of a trial subscription's quota.

    It is a declared exception: written down with its reason, not opened in
    the heat of a failing deploy.
  EOT
  type        = list(string)
  default     = []
}

variable "budget_amount" {
  description = "Monthly spend, in the subscription's billing currency, the budget alert is set against."
  type        = number
  default     = 50
}

variable "budget_contact_emails" {
  description = <<-EOT
    Addresses notified when the budget crosses its thresholds. Empty by
    default, and deliberately: an example address baked into this module
    would be somebody else's inbox by the time this landing zone is reused,
    silently notifying nobody who can act on it. With this empty, no budget
    is created at all: a budget nobody is watching is not a control.
  EOT
  type        = list(string)
  default     = []
}

variable "pod_cidr" {
  description = <<-EOT
    Address space the cluster's pods draw from under CNI Overlay. Declared
    here, not in the workload layer, because the cluster subnet's security
    group must admit it: traffic between pods on different nodes keeps the
    pods' own addresses on the wire, those addresses are outside the virtual
    network, and Azure's default rules drop them. live/lab/20-workload reads
    this value from this stack's state, so the two cannot drift apart.
  EOT
  type        = string
  default     = "192.168.0.0/16"
}
