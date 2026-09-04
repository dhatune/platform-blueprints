# The application firewall that sits in front of anything public.
#
# See ADR 20 for why. In short: this is not about the application being
# careless, it is about what arrives before the application gets a chance —
# and specifically about the window between a vulnerability being disclosed in
# something you depend on and the fix being deployed.

resource "google_compute_security_policy" "this" {
  name    = var.name
  project = var.project_id

  # Preview first, enforcement later, and this is the setting people skip.
  #
  # A maintained rule set turned straight to blocking rejects legitimate
  # traffic that nobody predicted, and the first report of it is a customer
  # rather than a log line. In preview the same requests are recorded and
  # served, so the exceptions can be found before anyone is turned away.
  #
  # The cost of preview is that it protects nothing while it runs, so it is a
  # phase with an end date rather than a setting.
  dynamic "rule" {
    for_each = var.managed_rule_sets

    content {
      action   = var.enforcing ? "deny(403)" : "allow"
      priority = rule.value.priority
      preview  = !var.enforcing

      match {
        expr {
          expression = "evaluatePreconfiguredExpr('${rule.value.expression}')"
        }
      }
      description = rule.value.description
    }
  }

  # Volume limiting, which is the part that works regardless of what the
  # request contains. It is also the part that protects the service from a
  # client that is not attacking it at all, only broken.
  rule {
    action   = "throttle"
    priority = 9000

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }

    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"

      # Per source address. Not per user, which this layer cannot see, and not
      # global, which would let one client exhaust the allowance for everyone.
      enforce_on_key = "IP"

      rate_limit_threshold {
        count        = var.rate_limit_per_minute
        interval_sec = 60
      }
    }

    description = "Per-source rate limit"
  }

  rule {
    action   = "allow"
    priority = 2147483647

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }

    description = "Default allow. Everything above decides what does not reach here."
  }

  # Logging every request, not only denials.
  #
  # A record of what was blocked answers what an attacker tried. A record of
  # everything answers whether a rule is turning away someone real, which is
  # the question that actually comes up.
  advanced_options_config {
    log_level = "VERBOSE"
  }
}
