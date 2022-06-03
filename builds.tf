resource "observe_dataset" "builds" {
  workspace = var.workspace.oid
  name      = format(var.name_format, "Builds")
  freshness = var.freshness_default
  inputs = {
    "buildEvents" = observe_dataset.build-events.oid
    "jobLogs"     = observe_dataset.build-logs.oid
  }

  stage {
    input    = "buildEvents"
    pipeline = <<-EOT
            union @jobLogs
            
            make_resource options(expiry:8h),
                queueSecs: queueSecs,
                buildSecs: buildSecs,
                slaveInfoExecutor: slaveInfoExecutor,
                slaveInfoSlaveName: slaveInfoSlaveName,
                scmInfoCommit: scmInfoCommit,
                scmInfoBranch: scmInfoBranch,
                buildCause: buildCause,
                ciUrl: ciUrl,
                buildUrl: buildUrl,
                link: strcat(ciUrl, buildUrl),
                scmInfoUrl: scmInfoUrl,
                buildFailureCauses: buildFailureCauses,
                result: result,
                startedUserName: startedUserName, 
                filename: filename,
                primary_key(jobName, buildNum, host, datacenter)
            make_col label: strcat(jobName,"/",string(buildNum))
            set_label label
        EOT
  }
}

resource "observe_link" "jenkins_builds" {
  workspace = var.workspace.oid
  source    = observe_dataset.builds.oid
  target    = each.value.target
  fields    = each.value.fields
  label     = each.key

  for_each = {
    "job" = {
      target = observe_dataset.jobs.oid
      fields = ["host", "datacenter", "jobName"]
    },
    "masterNode" = {
      target = observe_dataset.master-nodes.oid
      fields = ["host", "datacenter"]
    },
    // TODO - investigate Agent data in metrics
    //    "agent" = {
    //      target = observe_dataset.agents.oid
    //      fields = ["host", "datacenter", "agent"]
    //    },
  }
}

resource "observe_link" "build_logs" {
  workspace = var.workspace.oid
  source    = observe_dataset.build-logs.oid
  target    = each.value.target
  fields    = each.value.fields
  label     = each.key

  for_each = {
    "build" = {
      target = observe_dataset.builds.oid
      fields = ["host", "datacenter", "jobName", "buildNum"]
    },
    "build" = {
      target = observe_dataset.jobs.oid
      fields = ["host", "datacenter", "jobName"]
    },
    // TODO - investigate Agent data in metrics
    //    "agent" = {
    //      target = observe_dataset.agents.oid
    //      fields = ["host", "datacenter", "agent"]
    //    },
  }
}

resource "observe_board" "jenkins_builds" {
  dataset = observe_dataset.builds.oid
  name    = "Builds"
  type    = "set"
  json = templatefile("${path.module}/boards/builds.json", {
    dataset_builds      = observe_dataset.builds.id
    dataset_metrics     = observe_dataset.metrics.id
    dataset_masterNodes = observe_dataset.master-nodes.id
    dataset_jobs        = observe_dataset.jobs.id
  })
}