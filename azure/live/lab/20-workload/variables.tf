variable "subscription_id" {
  description = "Subscription everything is created in."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant that owns the key vault."
  type        = string
}

variable "prefix" {
  description = "Short organisation prefix."
  type        = string
}

variable "workload" {
  description = "Short workload identifier."
  type        = string
}

variable "location_short" {
  description = "Abbreviated region used in names."
  type        = string
}

# There is no location variable and no environment variable here: the region
# comes from the platform stack's location output, and the environment is
# fixed to "lab" the same way the platform stack fixes it. Restating either
# invites the two layers to disagree.

variable "platform_state_resource_group_name" {
  description = "Resource group holding the permanent layer's state storage account."
  type        = string
}

variable "platform_state_storage_account_name" {
  description = "Storage account holding the permanent layer's state."
  type        = string
}

variable "platform_state_container_name" {
  description = "Container holding the permanent layer's state blob."
  type        = string
}

variable "platform_state_key" {
  description = "Blob key of the permanent layer's state."
  type        = string
}

variable "node_vm_size" {
  description = <<-EOT
    System node pool size. Azure requires at least 2 vCPU and 4 GB for a
    system pool; this is the smallest shape that clears that floor (2 vCPU,
    4 GiB).

    The value must come from the list AKS itself returns when it rejects a
    size, not only from the general VM SKU catalogue: the catalogue reports a
    size as available in the region regardless of the per-subscription
    restrictions AKS enforces on top of it. Those are two independent
    catalogues -- a size present in only one is a gamble, and this one was
    confirmed present in both before being set as the default.
  EOT
  type        = string
  default     = "Standard_D2als_v7"
}

variable "node_count" {
  description = "Nodes in the system pool. One, for quota reasons stated in the design."
  type        = number
  default     = 1

  validation {
    condition     = var.node_count == 1
    error_message = "A trial subscription has four regional vCPUs in total. A two-vCPU node pool of two nodes would consume all of them, leaving no headroom for anything else this profile creates."
  }
}

variable "service_cidr" {
  description = "Address space Kubernetes services draw from. Must not overlap the virtual network or the pod range."
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "Address of the cluster DNS service. Must lie inside service_cidr."
  type        = string
  default     = "172.16.0.10"
}

variable "workload_service_account_namespace" {
  description = "Kubernetes namespace of the service account the workload identity's federated credential trusts. Defaults to check 4's probe namespace."
  type        = string
  default     = "check4-probe"
}

variable "workload_service_account_name" {
  description = "Kubernetes service account the workload identity's federated credential trusts. Defaults to check 4's probe service account."
  type        = string
  default     = "wi-probe"
}

variable "ingress_internal_address" {
  description = <<-EOT
    Private address the ingress controller's internal load balancer holds, and
    the address the firewall's destination-address translation points at.

    Fixed rather than allocated, because the translation rule is declared here
    and the load balancer is declared in Kubernetes: two systems that never
    talk to each other have to agree on this value somehow, and the only
    agreement that survives a redeploy of either side is a number both are
    told. The same value is set on the Kubernetes service through the
    provider's address annotation; scripts/lib/ingress.env carries it to that
    side, and this variable's default is what it carries.

    Must sit inside the cluster subnet and outside the range the nodes take.
    Nodes are assigned upward from the bottom of the subnet, so an address
    near the top stays free for as long as the cluster is one node.
  EOT
  type        = string
  default     = "10.61.1.240"
}

variable "ingress_source_addresses" {
  description = <<-EOT
    Addresses permitted to reach the ingress through the firewall. The
    firewall module refuses an empty list rather than widening it, so this
    value is always a deliberate statement.

    The default is every address, and that is a choice about this laboratory
    rather than a recommendation: the ephemeral layer is destroyed between
    sessions, nothing of value sits behind the ingress, and the purpose of
    the path is to be reached from outside and proven. Narrowing it to a
    single office address is a one-line change here -- and the vault, which is
    narrowed exactly that way, stopped answering the day the operator's
    address was reassigned, which is the cost that narrowing carries.
  EOT
  type        = list(string)
  default     = ["*"]
}

variable "allowed_egress_fqdns" {
  description = <<-EOT
    Named hosts the workload may reach on the web protocols, keyed by rule
    name. Empty by default, and that default is the point: the firewall's
    allow list is otherwise one FQDN tag Microsoft maintains, and every host
    added here is a deliberate hole in it.

    The first thing that asks for one is a continuous deployment agent that
    needs to reach a source repository. That is a real requirement and also a
    real decision: an agent inside the cluster with egress to a code host can
    fetch whatever that host will serve it, and the host is reached by name
    over TLS, which this tier cannot inspect. Naming the repository host
    rather than the whole forge is the narrowest form of it available here.

    Example, when the repository host is known:

      allowed_egress_fqdns = {
        source_repository = { destination_fqdns = ["<host of the repository>"] }
      }
  EOT

  type = map(object({
    destination_fqdns = list(string)
  }))
  default = {}
}
