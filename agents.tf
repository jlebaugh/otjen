resource "observe_dataset" "agents" {
  workspace = var.workspace.oid
  name      = format(var.name_format, "Agents")
  freshness = var.freshness_default
  inputs = {
    "Jenkins Events" = observe_dataset.events.oid
  }

  stage {
    alias    = "auditLogs"
    input    = "Jenkins Events"
    pipeline = <<-EOT
            filter @."_tag" = "jenkins_slave_logs"
            extract_regex filename, /slaves\/(?P<agent>.*)\//
            make_col label:agent

            pick_col timestamp, agent, label, host, datacenter
        EOT
  }
  /*    stage {
        alias    = "Change Logs_-fab6"
        input    = "Jenkins/Change Logs"
        pipeline = <<-EOT
            filter changeType="nodes"
            make_col agent: changeObject, xml:string(FIELDS.xml)
            filter match_regex(filename, /history.xml/)
            extract_regex xml, /.*\<user\>(?P<user>.*)\<\/user\>.*\<userId\>(?P<userId>.*)\<\/userId\>.*\<operation\>(?P<operation>.*)\<\/operation\>.*\<currentName\>(?P<currentName>.*)\<\/currentName\>.*\<oldName\>(?P<oldName>.*)\<\/oldName\>.*\<changeReasonComment\>(?P<changeReasonComment>.*)\<\/changeReasonComment\>/
        EOT
    }*/
  stage {
    alias    = "builds"
    input    = "Jenkins Events"
    pipeline = <<-EOT
            filter not is_null(slaveInfoSlaveName) AND slaveInfoSlaveName != ""
            make_col agent:slaveInfoSlaveName, label:slaveInfoLabel
            
            pick_col timestamp, agent, label, host, datacenter
        EOT
  }
  stage {
    pipeline = <<-EOT
            union @auditLogs
            union @builds
            
            make_resource
                label: label,
                primary_key(host, datacenter, agent)
            set_label label
        EOT
  }
}

resource "observe_board" "jenkins_agents" {
  dataset = observe_dataset.agents.oid
  name    = "Agents"
  type    = "set"
  json = templatefile("${path.module}/boards/agents.json", {
  })
}