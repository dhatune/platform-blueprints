variable "project_id" {
  description = "Project holding the policy. The same one as the load balancer it attaches to."
  type        = string
}

variable "name" {
  description = "Policy name, referenced by whatever attaches it to a backend."
  type        = string
}

variable "enforcing" {
  description = <<-EOT
    False records what would have been blocked and blocks nothing. True blocks.

    Start false, read what it recorded, then switch. Starting true turns away
    traffic nobody predicted and the first report is a complaint.
  EOT
  type        = bool
  default     = false
}

variable "managed_rule_sets" {
  description = <<-EOT
    Maintained rule sets to apply, by the platform's own expression names.
    Writing rules by hand is a second application to maintain, with no tests
    and one author; do it only to correct something the maintained set gets
    wrong.
  EOT
  type = list(object({
    priority    = number
    expression  = string
    description = string
  }))
  default = [
    { priority = 1000, expression = "sqli-v33-stable", description = "Database injection" },
    { priority = 1100, expression = "xss-v33-stable", description = "Cross-site scripting" },
    { priority = 1200, expression = "lfi-v33-stable", description = "Local file inclusion" },
    { priority = 1300, expression = "rce-v33-stable", description = "Remote code execution" },
    { priority = 1400, expression = "scannerdetection-v33-stable", description = "Scanners" },
    { priority = 1500, expression = "protocolattack-v33-stable", description = "Protocol attacks" },
    { priority = 1600, expression = "sessionfixation-v33-stable", description = "Session fixation" },
  ]
}

variable "rate_limit_per_minute" {
  description = "Requests per minute per source address before throttling."
  type        = number
  default     = 600
}
