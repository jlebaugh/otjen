resource "observe_dataset" "metrics" {
  workspace = var.workspace.oid
  name      = format(var.name_format, "Metrics")
  freshness = var.freshness_default
  inputs = {
    "Jenkins Events" = observe_dataset.events.oid
  }
  stage {
    alias    = "Duration"
    input    = "Jenkins Events"
    pipeline = <<-EOT
            filter @."_tag" = "jenkins_build"
            
            filter duration > 0
            
            
            make_col metrics:make_object("duration":duration)
            flatten_leaves metrics
            pick_col valid_from:timestamp,
              jobName, buildNum, metric_name:string(_c_metrics_path), metric_value:float64(_c_metrics_value), host, datacenter
              
            interface "metric", metric:metric_name, value:metric_value
            
        EOT
  }
  stage {
    alias    = "queueTime"
    input    = "Jenkins Events"
    pipeline = <<-EOT
            filter NOT is_null(queueTime) AND queueTime>0
            
            make_col metrics:make_object("queueTime":queueTime)
            flatten_leaves metrics
            pick_col valid_from:timestamp,
              jobName, buildNum, metric_name:string(_c_metrics_path), metric_value:float64(_c_metrics_value), host, datacenter, slaveInfoSlaveName
              
            interface "metric", metric:metric_name, value:metric_value
            
        EOT
  }
  stage {
    alias    = "Counts"
    input    = "Jenkins Events"
    pipeline = <<-EOT
            filter _tag="jenkins_build" and (result="SUCCESS" or result="FAILURE")
            
            timechart 1m, count:count(1), group_by(jobName, result, host, datacenter)
             
            make_event 
            
            make_col valid_from:(@."_c_valid_from")
            colshow _c_valid_from:true
            set_valid_from valid_from
            make_col metric_value:float64(count), metric_name:strcat(result, " Count")
            interface "metric", metric:result, value:metric_value
            
        EOT
  }
  stage {
    pipeline = <<-EOT
            interface "metric", metric:metric_name, value:metric_value
            union @Duration
            union @queueTime
            union @Counts
            
            pick_col valid_from, jobName, buildNum, metric_name, metric_value, host, datacenter, slaveInfoSlaveName
            
            set_metric options(label:"SUCCESS Count", unit:"",
              description:"Count",
              type:"gauge", rollup:"count", aggregate:"sum"),
              "SUCCESS Count"
              
            set_metric options(label:"FAILURE Count", unit:"",
              description:"Count",
              type:"gauge", rollup:"count", aggregate:"sum"),
              "FAILURE Count"
            
            set_metric options(label:"queueTime", unit:"ms",
              description:"average queueTime",
              type:"gauge", rollup:"avg", aggregate:"sum"),
              "queueTime"
              
            set_metric options(label:"duration", unit:"ms",
              description:"average duration",
              type:"gauge", rollup:"avg", aggregate:"sum"),
              "duration"
            
            set_metric options(label:"Change Count", unit:"",
              description:"Count",
              type:"gauge", rollup:"count", aggregate:"sum"),
              "Change Count"
            
        EOT
  }
}

resource "observe_link" "jenkins_metrics" {
  workspace = var.workspace.oid
  source    = observe_dataset.metrics.oid
  target    = each.value.target
  fields    = each.value.fields
  label     = each.key

  for_each = {
    "build" = {
      target = observe_dataset.builds.oid
      fields = ["host", "datacenter", "jobName", "buildNum"]
    },
    "job" = {
      target = observe_dataset.jobs.oid
      fields = ["host", "datacenter", "jobName"]
    },
    // TODO - investigate Agent data in metrics
    //    "agent" = {
    //      target = observe_dataset.agents.oid
    //      fields = ["host", "datacenter", "agent"]
    //    },
    "masterNode" = {
      target = observe_dataset.master-nodes.oid
      fields = ["host", "datacenter"]
    },
  }
}