# ============================================================================
# Variables
# ============================================================================

# ──────────────────────────────────────────────────────────────
# General
# ──────────────────────────────────────────────────────────────
variable "project" {
  description = "Project name"
  type        = string
  default     = "axiom"
}

variable "environment" {
  description = "Environment (staging, production)"
  type        = string
  default     = "staging"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be 'staging' or 'production'."
  }
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

# ──────────────────────────────────────────────────────────────
# VPC
# ──────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

# ──────────────────────────────────────────────────────────────
# EKS
# ──────────────────────────────────────────────────────────────
variable "kubernetes_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.29"
}

variable "node_instance_types" {
  description = "EC2 instance types for EKS managed node group"
  type        = list(string)
  default     = ["t3.large", "t3a.large"]
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 6
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 3
}

# ──────────────────────────────────────────────────────────────
# GitHub Actions OIDC
# ──────────────────────────────────────────────────────────────
variable "create_github_oidc" {
  description = "Create GitHub Actions OIDC provider and IAM role"
  type        = bool
  default     = true
}

variable "github_repository" {
  description = "GitHub repository (owner/repo) for OIDC trust"
  type        = string
  default     = "axiom-workflow-engine/axiom"
}
