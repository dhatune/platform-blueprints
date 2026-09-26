variable "name_prefix" {
  description = "Base name produced by the naming module."
  type        = string
}

variable "location" {
  description = "Azure region. No default on purpose."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the firewall is created in. The hub's."
  type        = string
}

variable "subnet_id" {
  description = "AzureFirewallSubnet. The data plane attaches here."
  type        = string
}

variable "management_subnet_id" {
  description = "AzureFirewallManagementSubnet. Firewall Basic puts its management NIC here."
  type        = string
}

variable "expected_private_ip" {
  description = <<-EOT
    The address the spoke's default route already points at. Azure assigns the
    firewall the first usable address of its subnet, and the route in the
    permanent layer is written before the firewall exists. Declaring the
    expectation here turns a silent black hole into a failed plan.
  EOT
  type        = string
}

variable "known_service_tags" {
  description = <<-EOT
    The Azure service tags this landing zone is allowed to reference in network
    rules. Service tags are a finite, Microsoft-published set, not a shape a
    regex can recognise -- a two-label hostname such as "docker.io" is
    syntactically identical to a two-label regional tag such as
    "AzureCloud.eastus2", and "AzureCloud.evil-attacker-domain.invalid" carries a
    real, known first label. An unknown tag must be refused loudly at plan
    time, never deployed inert.

    A tag that itself contains a dot, such as "AzureFrontDoor.FirstParty", is
    added here as that exact whole string. It is matched by full-string
    equality (branch b of the allowed_service_tags validation), not by
    splitting on "." and checking a region suffix (branch c) -- there is no
    region here, and decomposing it would either reject it outright or, worse,
    accept some other unrelated "AzureFrontDoor.<anything-lowercase>".
  EOT
  type        = list(string)
  default = [
    "AzureCloud",
    "AzureActiveDirectory",
    "AzureContainerRegistry",
    "AzureKeyVault",
    "AzureMonitor",
    "Storage",
    "Sql",
    "MicrosoftContainerRegistry",
    "GuestAndHybridManagement",
    "AzureUpdateDelivery",
    "VirtualNetwork",
    "AzureLoadBalancer",
    "Internet",
  ]
}

variable "allowed_source_addresses" {
  description = <<-EOT
    Sources permitted to use the service-tag network rules and the
    Microsoft-maintained FQDN tag application rules below. Egress through
    this firewall is only ever exercised by the spoke, so the caller passes
    the spoke's own address space here rather than "*" -- a rule read as
    "anything on the internet may originate this traffic" is a materially
    different claim from "anything in this landing zone's own network may",
    even though both filter on protocol, tag and port identically.

    No default: a caller has to decide this rather than inherit a wildcard.
  EOT
  type        = list(string)
}

variable "allowed_service_tags" {
  description = <<-EOT
    Destinations permitted as network rules, keyed by rule name. Basic has no
    DNS proxy, so network rules cannot filter by FQDN -- only by service tag or
    address. A rule written with an FQDN here would be accepted by the provider
    and would never match.
  EOT

  type = map(object({
    protocols             = list(string)
    destination_addresses = list(string)
    destination_ports     = list(string)
  }))

  default = {}

  # This defines what is VALID and refuses everything else. A guard that
  # describes what is invalid always leaves something out: a regex cannot tell
  # "docker.io" from "AzureCloud.eastus2" (same shape), and checking only the
  # first label lets "AzureCloud.evil-attacker-domain.invalid" through because
  # "AzureCloud" really is a known tag and the rest of the string is never
  # examined. A destination is accepted only if:
  #   (a) it parses as a CIDR or a single address; or
  #   (b) it is EXACTLY a member of known_service_tags (full-string equality,
  #       no splitting) -- this is how a tag that itself contains a dot, such
  #       as "AzureFrontDoor.FirstParty", is accepted; or
  #   (c) it splits on "." into EXACTLY two parts, where part one is exactly a
  #       known tag and part two is a bare lowercase-alphanumeric region token
  #       (no hyphens, no further dots) -- "AzureCloud.eastus2" matches this;
  #       "AzureCloud.evil-attacker-domain.invalid" does not (three parts, not two).
  # Anything else -- any other shape -- is refused. Without this validation
  # the mistake reaches Azure, deploys green, and filters nothing.
  validation {
    condition = alltrue([
      for r in values(var.allowed_service_tags) : alltrue([
        for d in r.destination_addresses :
        can(cidrnetmask(strcontains(d, "/") ? d : "${d}/32")) ||
        contains(var.known_service_tags, d) ||
        (
          length(split(".", d)) == 2 &&
          contains(var.known_service_tags, split(".", d)[0]) &&
          can(regex("^[a-z0-9]+$", split(".", d)[1]))
        )
      ])
    ])
    error_message = "A network rule destination must be an address, a CIDR, an exact known service tag, or a known service tag followed by exactly one lowercase-alphanumeric region label (Tag.region). See var.known_service_tags. Azure Firewall Basic has no DNS proxy, so a destination written as a hostname deploys without error and matches nothing."
  }
}

variable "allowed_fqdn_tags" {
  description = <<-EOT
    Microsoft-maintained FQDN tags permitted as application rules. Basic does
    support these, and AzureKubernetesService is what lets a cluster with
    userDefinedRouting egress reach its own control plane and image sources.
  EOT
  type        = list(string)
  default     = []
}

variable "allowed_fqdns" {
  description = <<-EOT
    Egress permitted to named hosts, keyed by rule name. Separate from
    allowed_fqdn_tags because those name lists Microsoft maintains and these
    name hosts this landing zone chose -- a distinction worth keeping visible,
    since one of them is somebody else's responsibility to keep correct and
    the other is ours.

    These are APPLICATION rules, which is the only kind that can filter by
    name here: filtering by name in a NETWORK rule needs the DNS proxy, and
    the Basic tier has none (docs/decisions/0010). So this covers HTTP and
    HTTPS and nothing else. A host reached over any other protocol needs a
    service tag or an address, not a name.

    The default is empty on purpose. Every entry is a hole in the egress
    policy, and the first thing that asks for one is usually a deployment
    tool wanting to reach a source repository -- which is worth deciding
    deliberately rather than inheriting. A continuous deployment agent with
    egress to a code host can fetch whatever that host will serve it.
  EOT

  type = map(object({
    destination_fqdns = list(string)
  }))

  default = {}

  validation {
    condition = alltrue([
      for r in values(var.allowed_fqdns) : length(r.destination_fqdns) > 0
    ])
    error_message = "Every entry in allowed_fqdns must name at least one host. An entry with an empty list creates a rule that permits nothing, which reads in the portal as an allow rule and behaves as a deny."
  }
}

variable "inbound_nat_rules" {
  description = <<-EOT
    Inbound destination-address translation onto the firewall's own public
    address, keyed by rule name. This is the module's only path for letting
    traffic in: it reuses the address the firewall already holds rather than
    provisioning a second one, because the subscription's public-address
    quota is three and the firewall's two ip_configurations already take two
    of them.

    The destination of a NAT rule is always the firewall's own public
    address, and the module already knows it (azurerm_public_ip.data) -- the
    caller supplies destination_port only, never the address itself. Making
    the caller restate the address invites the caller's copy and the
    firewall's actual address to drift apart.

    No extra route is needed for the reply. The firewall translates the
    source of DNAT traffic to its own private address, so the reply returns
    to it over the peering and never consults the spoke's route table.
  EOT

  type = map(object({
    protocols          = list(string)
    source_addresses   = optional(list(string), [])
    destination_port   = string
    translated_address = string
    translated_port    = number
  }))

  default = {}

  # source_addresses defaults to an empty list rather than "*" specifically so
  # it can be refused here. A NAT rule forwards onto a firewall's public
  # address -- defaulting an omitted source to permissive would turn a
  # caller's oversight into every address on the internet being allowed to
  # reach an internal port. Refusing the empty case forces every rule to name
  # its permitted sources explicitly.
  validation {
    condition = alltrue([
      for r in values(var.inbound_nat_rules) : length(r.source_addresses) > 0
    ])
    error_message = "Every entry in inbound_nat_rules must list explicit source_addresses. There is no permissive default here: a NAT rule exposes an internal address and port on the firewall's public IP, so an omitted source must be refused at plan time, not silently widened to \"*\"."
  }
}

variable "tags" {
  description = "Tags produced by the naming module."
  type        = map(string)
}
