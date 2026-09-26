variable "name_prefix" {
  description = "Base name produced by the naming module."
  type        = string
}

variable "location" {
  description = "Azure region. No default on purpose."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the cluster object is created in."
  type        = string
}

variable "subnet_id" {
  description = <<-EOT
    Subnet the nodes attach to. It must already carry the route table whose
    default route points at the firewall: with userDefinedRouting egress, AKS
    validates the route at creation and refuses a subnet without one.
  EOT
  type        = string
}

variable "node_vm_size" {
  description = <<-EOT
    Size of the system node pool. Azure requires at least 2 vCPU and 4 GB for a
    system pool, which is also the whole budget a trial subscription can spare.
  EOT
  type        = string
}

variable "node_count" {
  description = "Nodes in the system pool."
  type        = number

  validation {
    condition     = var.node_count >= 1
    error_message = "A cluster needs at least one node."
  }
}

variable "pod_cidr" {
  description = <<-EOT
    Address space pods draw from. Under CNI Overlay this is NOT part of the
    virtual network, which is what keeps a /24 node subnet from capping the
    cluster at 256 pods. It must not overlap the virtual network.
  EOT
  type        = string
}

variable "service_cidr" {
  description = "Address space Kubernetes services draw from. Must not overlap the virtual network or the pod range."
  type        = string

  # Overlapping pod and service ranges are accepted by the provider and produce
  # a cluster whose service addresses shadow real pod addresses. The symptom is
  # intermittent and looks like a DNS fault.
  #
  # The base of each range is taken with cidrhost(cidr, 0), which masks the
  # address down to its network, rather than split("/", cidr)[0], which takes
  # the address exactly as written. A non-canonical CIDR such as
  # "10.61.0.0/8" defeats the latter: split(...)[0] reads it as "10.61.0.0"
  # while its real network base is "10.60.0.0", so a range that does overlap
  # plans clean.
  validation {
    condition = !(
      sum([for i, o in split(".", cidrhost(var.pod_cidr, 0)) : tonumber(o) * pow(256, 3 - i)])
      < sum([for i, o in split(".", cidrhost(var.service_cidr, 0)) : tonumber(o) * pow(256, 3 - i)]) + pow(2, 32 - tonumber(split("/", var.service_cidr)[1]))
      &&
      sum([for i, o in split(".", cidrhost(var.service_cidr, 0)) : tonumber(o) * pow(256, 3 - i)])
      < sum([for i, o in split(".", cidrhost(var.pod_cidr, 0)) : tonumber(o) * pow(256, 3 - i)]) + pow(2, 32 - tonumber(split("/", var.pod_cidr)[1]))
    )
    error_message = "The pod and service ranges overlap. The provider accepts this and the cluster fails intermittently in a way that looks like a DNS fault."
  }
}

variable "dns_service_ip" {
  description = "Address of the cluster DNS service. Must lie inside service_cidr."
  type        = string

  validation {
    condition     = can(cidrhost("${var.dns_service_ip}/32", 0))
    error_message = "dns_service_ip must be a single address."
  }

  # Cross-variable validation, which needs Terraform 1.9. Comparing octets or
  # string prefixes catches only the crudest mistake: 172.16.0.10 and
  # 172.17.0.10 share a first octet and the second is outside a /16. Addresses
  # are compared as integers, the same way the platform stack's overlap guard
  # does it.
  #
  # service_cidr's base is taken with cidrhost(service_cidr, 0), not
  # split("/", service_cidr)[0]: the latter takes the address as written, so a
  # non-canonical CIDR such as "172.16.128.0/16" reads its base as
  # "172.16.128.0" instead of the real network base "172.16.0.0", and an
  # address the real range excludes plans clean.
  validation {
    condition = (
      sum([for i, o in split(".", var.dns_service_ip) : tonumber(o) * pow(256, 3 - i)])
      >= sum([for i, o in split(".", cidrhost(var.service_cidr, 0)) : tonumber(o) * pow(256, 3 - i)])
      &&
      sum([for i, o in split(".", var.dns_service_ip) : tonumber(o) * pow(256, 3 - i)])
      < sum([for i, o in split(".", cidrhost(var.service_cidr, 0)) : tonumber(o) * pow(256, 3 - i)]) + pow(2, 32 - tonumber(split("/", var.service_cidr)[1]))
    )
    error_message = "dns_service_ip must lie inside service_cidr. A cluster whose DNS address is outside its own service range comes up and resolves nothing."
  }
}

variable "acr_id" {
  description = "Registry the kubelet identity is granted pull rights on."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant the cluster authenticates against. Supplied by the caller; never discovered."
  type        = string
}

variable "admin_group_object_ids" {
  description = <<-EOT
    Entra object ids of groups granted cluster administration through Azure
    RBAC. Granting the assignment to a group rather than to individual people
    is what makes it survive staff changes: membership moves, the role
    assignment does not. An empty list is valid -- it means cluster
    administration is granted by Azure role assignment alone, with no group
    holding the built-in admin claim.
  EOT
  type        = list(string)
  default     = []
}

variable "route_table_id" {
  description = <<-EOT
    Route table the control plane identity is granted Network Contributor on,
    alongside the subnet itself (var.subnet_id). The cluster does not own
    either the subnet or the route table, and with userDefinedRouting it must
    be able to read both. Scoped to exactly these two objects, not to the
    resource group they live in: the identity that manages this cluster's
    network path has no business reading or touching anything else the
    resource group happens to hold.
  EOT
  type        = string
}

variable "kubernetes_version" {
  description = <<-EOT
    Kubernetes version to pin the control plane and the default node pool to.
    Left null by default, which lets Azure choose its own current default --
    this module does not invent a version number to hardcode, since whatever
    is written here ages the moment it is committed.
  EOT
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags produced by the naming module."
  type        = map(string)
}
