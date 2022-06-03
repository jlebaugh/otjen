resource "observe_dataset" "jobs" {
  workspace = var.workspace.oid
  name      = format(var.name_format, "Jobs")
  freshness = var.freshness_default
  inputs = {
    "Jenkins Events" = observe_dataset.events.oid
  }

  stage {
    alias    = "Stats_Collector_Events"
    input    = "Jenkins Events"
    pipeline = <<-EOT
            filter match_regex(@."_tag",/^jenkins_project(s?)$/) 
            
            pick_col timestamp, 
                jobName:string(FIELDS.name),
                host:string(FIELDS.host),
                datacenter:string(FIELDS.datacenter),
                status:string(FIELDS.status),
                ciUrl:string(FIELDS.ciUrl),
                jobUrl:string(FIELDS.jobUrl),
                link: strcat(string(FIELDS.ciUrl),string(FIELDS.jobUrl)),
            	configFile:string(FIELDS.configFile),
                createdDate:from_milliseconds(int64(FIELDS.createdDate)),
                updatedDate:from_milliseconds(int64(FIELDS.updatedDate)),
                userId:string(FIELDS.userId),
                userName:string(FIELDS.userName)
            //set_link "jobUrl1", jobUrl: @"stage-q8u5irxn".jobUrl
        EOT
  }
  stage {
    alias    = "Job_Logs"
    input    = "Jenkins Events"
    pipeline = <<-EOT
            //TO-DO: why does this filter break it?
            //filter _tag="jenkins_job_logs"
            pick_col timestamp, jobName, host, datacenter

            //create a quick table
            timechart 5m,
                group_by(jobName, host, datacenter)

            //back to event
            make_event
        EOT
  }
  stage {
    pipeline = <<-EOT
            union @Stats_Collector_Events
            union @Job_Logs
            
            make_resource options(expiry:30d),
                status: status,
                ciUrl: ciUrl,
                jobUrl: jobUrl,
                link: link,
                configFile: configFile,
                createdDate: createdDate,
                updatedDate: updatedDate,
                userId: userId,
                userName: userName, 
                primary_key(host, datacenter, jobName)
            set_label jobName
        EOT
  }
}

resource "observe_link" "jenkins_jobs" {
  workspace = var.workspace.oid
  source    = observe_dataset.jobs.oid
  target    = each.value.target
  fields    = each.value.fields
  label     = each.key

  for_each = {
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

resource "observe_board" "jenkins_jobs" {
  dataset = observe_dataset.jobs.oid
  name    = "Jobs"
  type    = "set"
  json = templatefile("${path.module}/boards/jobs.json", {
    dataset_metrics     = observe_dataset.metrics.id
    dataset_masterNodes = observe_dataset.master-nodes.id
    dataset_jobs        = observe_dataset.jobs.id
  })
}