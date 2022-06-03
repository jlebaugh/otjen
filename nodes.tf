resource "observe_dataset" "master-nodes" {
  workspace = var.workspace.oid
  name      = format(var.name_format, "Master Nodes")
  freshness = var.freshness_default
  inputs = {
    "Jenkins Events" = observe_dataset.events.oid
  }

  stage {
    pipeline = <<-EOT
            make_resource options(expiry:7d),
            	primary_key(host, datacenter)
            
            make_col label:strcat(datacenter, "/", host)
            set_label label
        EOT
  }
}

//resource "observe_link" "jenkins_master_nodes" {
//  workspace = var.workspace.oid
//  source    = observe_dataset.master-nodes.oid
// target    = each.value.target
//  fields    = each.value.fields
//  label     = each.key

//  for_each = {
// TODO - link to linux host monitoring
//      "masterNode" = {
//      target = observe_dataset.master-nodes.oid
//      fields = ["host", "datacenter"]
//    },
// TODO - investigate Agent data in metrics
//    "agent" = {
//      target = observe_dataset.agents.oid
//      fields = ["host", "datacenter", "agent"]
//    },
//  }
//}

resource "observe_board" "jenkins_master-nodes" {
  dataset = observe_dataset.master-nodes.oid
  name    = "Master Nodes"
  type    = "set"
  json = templatefile("${path.module}/boards/master.json", {
    dataset_metrics     = observe_dataset.metrics.id
    dataset_masterNodes = observe_dataset.master-nodes.id
  })
}
