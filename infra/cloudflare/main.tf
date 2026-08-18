terraform {
  required_version = "~> 1.12"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

variable "account_id" {
  description = "Cloudflare account ID that owns the zone and Pages project."
  type        = string
}

variable "zone_name" {
  description = "Zone name (apex domain) for this site."
  type        = string
  default     = "cade.io"
}

variable "pages_project_name" {
  description = "Cloudflare Pages project name."
  type        = string
  default     = "dotfiles"
}

variable "pages_custom_domain" {
  description = "Custom domain to bind to the Pages project."
  type        = string
  default     = "dotfiles.cade.io"
}

variable "pages_production_branch" {
  description = "Git branch used for production deploys."
  type        = string
  default     = "main"
}

variable "github_owner" {
  description = "GitHub org or user that owns the repo."
  type        = string
}

variable "github_repo" {
  description = "GitHub repo name for the Pages project."
  type        = string
  default     = "dotfiles"
}

provider "cloudflare" {}

data "cloudflare_zone" "apex" {
  filter = {
    name = var.zone_name
  }
}

resource "cloudflare_pages_project" "site" {
  account_id        = var.account_id
  name              = var.pages_project_name
  production_branch = var.pages_production_branch

  build_config = {
    # build.sh fetches pinned prebuilt mdbook + mdbook-mermaid, then runs `mdbook build docs`
    build_command   = "bash infra/cloudflare/build.sh"
    destination_dir = "docs/book"
    root_dir        = ""
  }

  source = {
    type = "github"
    config = {
      owner             = var.github_owner
      repo_name         = var.github_repo
      production_branch = var.pages_production_branch
    }
  }

  deployment_configs = {
    preview = {
      fail_open = false
    }
    production = {
      fail_open = false
    }
  }
}

resource "cloudflare_pages_domain" "site" {
  account_id   = var.account_id
  project_name = cloudflare_pages_project.site.name
  name         = var.pages_custom_domain
}

# dotfiles.cade.io → <project>.pages.dev (proxied through Cloudflare)
resource "cloudflare_dns_record" "site" {
  zone_id = data.cloudflare_zone.apex.id
  type    = "CNAME"
  name    = var.pages_custom_domain
  content = cloudflare_pages_project.site.subdomain
  proxied = true
  ttl     = 1
}

moved {
  from = cloudflare_record.site
  to   = cloudflare_dns_record.site
}

output "pages_project_name" {
  value = cloudflare_pages_project.site.name
}

output "pages_project_subdomain" {
  value = cloudflare_pages_project.site.subdomain
}

output "pages_domain_status" {
  value = cloudflare_pages_domain.site.status
}
