# tflint's settings for infra/ (run by the Terraform CI job; see "Infrastructure" in TESTING.md).
# The built-in Terraform rules only, for now. Add the provider's ruleset (tflint-ruleset-google) once
# the GCP migration defines resources here.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
