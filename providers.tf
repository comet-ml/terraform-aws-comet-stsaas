# No provider "aws" configuration block here — on purpose.
#
# This module is consumed as a child module (module "comet" { source = "...?ref=" }),
# so it must NOT declare its own provider config. A child module's provider block
# takes precedence for the module's resources and IGNORES the caller's provider,
# which strips the wrapper's control over credentials (assume_role / profile /
# region) and default_tags. That is the deprecated pattern.
#
# The module only declares its provider *requirement* (versions.tf →
# required_providers). Credential + region + default_tags configuration is owned
# by the CALLER's `provider "aws"` block, which the module inherits.
#
# Wrappers: put region, the assume_role/profile, and default_tags on YOUR
# provider "aws" — everything in this module runs through it.
