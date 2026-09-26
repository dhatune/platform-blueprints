variables {
  prefix         = "ops"
  workload       = "alz"
  environment    = "lab"
  location_short = "eus2"
  instance       = "01"
}

run "base_name_is_joined_and_lowercased" {
  command = plan

  assert {
    condition     = output.base == "ops-alz-lab-eus2-01"
    error_message = "base must join prefix, workload, environment, location and instance with dashes"
  }
}

run "storage_base_is_alphanumeric_and_within_limit" {
  command = plan

  assert {
    condition     = can(regex("^[a-z0-9]{3,24}$", output.storage_base))
    error_message = "storage_base must be 3-24 lowercase alphanumeric characters with no dashes"
  }

  assert {
    condition     = output.storage_base == "opsalzlabeus201"
    error_message = "storage_base must be base with every non-alphanumeric character removed"
  }
}

run "tags_carry_the_required_keys" {
  command = plan

  assert {
    condition     = alltrue([for k in ["environment", "workload", "managed_by"] : contains(keys(output.tags), k)])
    error_message = "tags must always carry environment, workload and managed_by"
  }

  assert {
    condition     = output.tags["managed_by"] == "terraform"
    error_message = "managed_by must state that the resource is managed by terraform"
  }
}

run "environment_is_validated_by_shape_not_by_a_fixed_list" {
  command = plan

  # environment is checked the same generic way as prefix, workload and
  # location_short -- neither a fixed enum of named profiles this module
  # would otherwise have to know about, nor unchecked. Both directions are
  # exercised: a shape this landing zone does not currently use anywhere must
  # still be accepted, and one that violates the shape must still be refused.
  variables {
    environment = "stage"
  }

  assert {
    condition     = output.base == "ops-alz-stage-eus2-01"
    error_message = "a syntactically valid environment this repository does not happen to ship must still be accepted"
  }
}

run "an_environment_that_violates_the_shape_is_refused" {
  command = plan

  variables {
    environment = "Lab-1"
  }

  expect_failures = [var.environment]
}

run "extra_tags_are_merged_and_cannot_drop_required_keys" {
  command = plan

  variables {
    # managed_by collides on purpose: a non-colliding key cannot detect a
    # merge-precedence regression, which makes the assertion a tautology.
    extra_tags = {
      owner      = "platform"
      managed_by = "someone-else"
    }
  }

  assert {
    condition     = output.tags["owner"] == "platform"
    error_message = "extra_tags must be merged into the result"
  }

  assert {
    condition     = output.tags["managed_by"] == "terraform"
    error_message = "a colliding extra_tag must never displace a required key"
  }
}
