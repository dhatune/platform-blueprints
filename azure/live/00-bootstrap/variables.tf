variable "prefix" {
  description = "Short organisation prefix."
  type        = string
}

variable "workload" {
  description = "Short workload identifier."
  type        = string
}

variable "environment" {
  description = "Deployment profile."
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
  description = "Subscription the state storage is created in."
  type        = string
}

variable "state_retention_days" {
  description = "Days a deleted or overwritten state file remains recoverable."
  type        = number
  default     = 30
}
