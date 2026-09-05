# Organization policy constraints.
#
# Everything else in this landing zone is a grant: someone is given a role, and
# anyone who can grant roles can grant a different one. A constraint is the
# other kind of control. It is a limit rather than a permission, and a project
# owner cannot remove it, only somebody with authority over the policy itself,
# at a level above the project, can.
#
# That distinction is why this module exists. It is the difference between a
# decision that is written down and a decision that holds.

# Makes the no-keys decision real rather than aspirational.
#
# Without this, "we do not use service account keys" is a convention, and
# conventions are broken by whoever is unblocking a deployment at midnight , 
# correctly, from their point of view, because the alternative is a broken
# deployment. The constraint moves that decision out of the moment.
resource "google_org_policy_policy" "no_service_account_keys" {
  name   = "${var.parent}/policies/iam.disableServiceAccountKeyCreation"
  parent = var.parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# Restricts who can appear in any IAM policy to the organization's own
# identities. Without it, a single mistyped or careless binding can grant a
# personal account outside the company access to a production project, and
# nothing about that binding looks unusual in a diff.
#
# Note the value: this constraint takes Cloud Identity customer IDs, not domain
# names. Passing a domain produces a policy that applies to nothing while
# reporting success, which is the worst possible outcome for a control.
resource "google_org_policy_policy" "allowed_domains" {
  name   = "${var.parent}/policies/iam.allowedPolicyMemberDomains"
  parent = var.parent

  spec {
    rules {
      values {
        allowed_values = var.allowed_customer_ids
      }
    }
  }
}

# No external IP addresses on virtual machines by default.
#
# A public address is the difference between a host that is exposed to the
# internet and one that is not, and it is set by whoever creates the machine,
# usually by accepting a default. Denying it here means reaching a workload
# from outside requires deliberately building a way in: a load balancer, a
# gateway, which is a reviewable act rather than a checkbox.
resource "google_org_policy_policy" "no_external_ip" {
  name   = "${var.parent}/policies/compute.vmExternalIpAccess"
  parent = var.parent

  spec {
    rules {
      deny_all = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "no_public_sql" {
  name   = "${var.parent}/policies/sql.restrictPublicIp"
  parent = var.parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "storage_public_access" {
  name   = "${var.parent}/policies/storage.publicAccessPrevention"
  parent = var.parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "require_os_login" {
  name   = "${var.parent}/policies/compute.requireOsLogin"
  parent = var.parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# Stops the platform from automatically granting broad roles to the default
# service accounts it creates, which is where a surprising amount of unearned
# permission comes from.
#
# This one has a real cost that is worth knowing before enabling it: the build
# process for some managed runtimes relies on exactly those automatic grants,
# and enabling this breaks them with an error that does not mention policy at
# all. The exception belongs at the folder holding those workloads, not at the
# organization, so the rest of the estate keeps the protection. That is what
# exempt_folders is for.
resource "google_org_policy_policy" "no_automatic_grants" {
  name   = "${var.parent}/policies/iam.automaticIamGrantsForDefaultServiceAccounts"
  parent = var.parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "automatic_grants_exception" {
  for_each = toset(var.exempt_folders)

  name   = "folders/${each.value}/policies/iam.automaticIamGrantsForDefaultServiceAccounts"
  parent = "folders/${each.value}"

  spec {
    # An exception is a decision with a reason and an owner. Recording it as
    # configuration rather than as a change someone made in the console once is
    # the only way it gets revisited.
    rules {
      enforce = "FALSE"
    }
  }
}
