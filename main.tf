data "observe_dataset" "observation" {
  workspace = var.workspace.oid
  name      = var.observation_dataset
}
