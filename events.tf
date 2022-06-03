resource "observe_dataset" "events" {
  workspace = var.workspace.oid
  name      = format(var.name_format, "Events")
  freshness = var.freshness_default

  inputs = {
    "observation" = data.observe_dataset.observation.oid
  }

  stage {
    pipeline = <<-EOT
            make_col path:string(EXTRA.path)
            filter match_regex(path, /jenkins/) OR path="/fluentd/"
            
            make_col number:int64(FIELDS.number), jobName:string(FIELDS.jobName), duration:int64(FIELDS.duration), startTime:int64(FIELDS.startTime), 
               startedUserId:string(FIELDS.startedUserId), startedUserName:string(FIELDS.startedUserName), host:string(FIELDS.host), log:string(FIELDS.log), 
               fluentTimestamp:int64(FIELDS.fluentTimestamp), entryTime:int64(FIELDS.entryTime), exitTime:int64(FIELDS.exitTime), result:string(FIELDS.result), 
               queueTime:int64(FIELDS.queueTime), datacenter:string(FIELDS.datacenter), buildCause:string(FIELDS.buildCause),
               buildFailureCauses:string(FIELDS.buildFailureCauses), buildUrl:string(FIELDS.buildUrl), ciUrl:string(FIELDS.ciUrl),
               filename:string(FIELDS.filename), _tag:string(FIELDS._tag), scmInfoBranch:string(FIELDS.scmInfo.branch),
                scmInfoCommit:string(FIELDS.scmInfo.commit),
                scmInfoUrl:string(FIELDS.scmInfo.url),
                slaveInfoExecutor:string(FIELDS.slaveInfo.executor),
                slaveInfoLabel:string(FIELDS.slaveInfo.label),
                slaveInfoSlaveName:string(FIELDS.slaveInfo.slaveName)
            
            //clean up td-agent-bit (fluentbit) tags
            make_col _tag:rtrim(_tag, '_')
            //clean up tags from td-agent (fluentd) 
            make_col _tag:replace(_tag, '.', '_')
            //clean up observe from tags
            make_col _tag:replace(_tag,"observe_","")
            
            make_col timestamp:from_nanoseconds((int64(FIELDS.fluentTimestamp)))
            set_valid_from timestamp
            
            //Extract from job and and build num from log file obsevations via filepaths
            extract_regex filename, /jobs\/(?P<jobName_tmp1>.*)\/builds\/(?P<buildNum_tmp1>\d*)\//
            
            //extract job and build num from URL in observations that include that
            extract_regex buildUrl, /job\/(?P<jobName_tmp2>.*)\/(?P<buildNum_tmp2>\d*)\//
            
            //clean up the data
            make_col buildNum_tmp1:int64(buildNum_tmp1), buildNum_tmp2:int64(buildNum_tmp2)
            
            //combine jobnames and buildnums from different observation types into one field
            make_col jobName:coalesce(jobName, jobName_tmp1, jobName_tmp2), buildNum:coalesce(number, buildNum_tmp1, buildNum_tmp2)
            
            // clean up URL job scrape whitespace
            make_col jobName:replace(jobName, "%20", " ")
            
            pick_col timestamp, _tag, jobName, buildNum, datacenter, host, startTime, entryTime, exitTime, queueTime, startedUserId, startedUserName, duration, result, filename, log, ciUrl, buildUrl, buildCause, buildFailureCauses, scmInfoBranch:string(FIELDS.scmInfo.branch),
                scmInfoCommit,
                scmInfoUrl,
                slaveInfoExecutor,
                slaveInfoLabel,
                slaveInfoSlaveName, FIELDS
        EOT
  }
}

resource "observe_dataset" "build-events" {
  workspace = var.workspace.oid
  name      = format(var.name_format, "Build Events")
  freshness = var.freshness_default
  inputs = {
    "Jenkins Events" = observe_dataset.events.oid
  }

  stage {
    input    = "Jenkins Events"
    pipeline = <<-EOT
            filter match_regex(@."_tag",/^jenkins_build(s?)$/) 
            make_col queueTime_1:int64(FIELDS.queueTime),
                duration_1:int64(FIELDS.duration)
            make_col parameters:FIELDS.parameters
            
            make_col
              buildCause:case(strlen(buildCause) > 0, buildCause),
              buildSecs:case(duration > 0, duration / 1000),
              queueSecs:case(queueTime > 0, queueTime_1 / 1000),
              startedUserName:case(strlen(startedUserName) > 0, startedUserName),
              startTime:from_milliseconds(int64(FIELDS.startTime)), endTime:from_milliseconds(int64(FIELDS.endTime)),
              slaveInfoExecutor:case(strlen(slaveInfoExecutor) > 0, slaveInfoExecutor),
              slaveInfoSlaveName:case(strlen(slaveInfoSlaveName) > 0, slaveInfoSlaveName),
              parameters:case(string(parameters) != "{}", parameters),
              scmBranch:string(FIELDS.scmInfo.branch),
              scmCommit:string(FIELDS.scmInfo.commit),
              scmUrl:string(FIELDS.scmInfo.url)
        EOT
  }
}

resource "observe_dataset" "build-logs" {
  workspace = var.workspace.oid
  name      = format(var.name_format, "Build Logs")
  freshness = var.freshness_default
  inputs = {
    "Jenkins Events" = observe_dataset.events.oid
  }

  stage {
    input    = "Jenkins Events"
    pipeline = <<-EOT
            filter match_regex(filename, /jobs/)
            
            pick_col timestamp, jobName, buildNum, host, datacenter, filename, log
            set_label jobName
        EOT
  }
}


resource "observe_dataset" "audit-logs" {
  workspace = var.workspace.oid
  name      = format(var.name_format, "Audit Logs")
  freshness = var.freshness_default
  inputs = {
    "Jenkins Events" = observe_dataset.events.oid
  }

  stage {
    pipeline = "filter match_regex(filename, /logs/)"
  }
}

resource "observe_dataset" "queue-events" {
  workspace = var.workspace.oid
  name      = format(var.name_format, "Queue Events")
  freshness = var.freshness_default
  inputs = {
    "Jenkins Events" = observe_dataset.events.oid
  }

  stage {
    pipeline = <<-EOT
            
            filter @."_tag" = "jenkins_queue"
            make_col type:string(FIELDS.queueCauses[0].type),
                reasonForWaiting:string(FIELDS.queueCauses[0].reasonForWaiting),
                exitTime_1:int64(FIELDS.queueCauses[0].exitTime),
                entryTime_1:int64(FIELDS.queueCauses[0].entryTime)
                
            make_col entryTime: from_milliseconds(int64(entryTime)), exitTime: from_milliseconds(int64(exitTime)) 
            pick_col  timestamp, jobName, buildNum, host, datacenter, entryTime, exitTime, type, reasonForWaiting
        EOT
  }
}