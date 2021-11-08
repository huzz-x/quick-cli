sync() {
  local project_pipeline_id_arr
  local pipeline_id_arr
  IFS=" " read -r -a project_pipeline_id_arr <<< "$project_pipeline_ids"
  local project_id
  local pipeline_ids
  local success_pipeline_count=0
  local total_pipeline_count=0

  ## 循环一轮计算Pipeline总数, 打印Pipeline
  for project_pipeline_id in "${project_pipeline_id_arr[@]}"; do
    pipeline_ids=$(echo "$project_pipeline_id" | cut -d# -f2)
    IFS="," read -r -a pipeline_id_arr <<< "$pipeline_ids"
    for pipeline_id in "${pipeline_id_arr[@]}"; do
      total_pipeline_count=$((total_pipeline_count+1))
    done
  done
  info_log "Total Pipeline: $total_pipeline_count"

  local web_url
  local status
  local pipeline_has_failure
  local log_buf
  local status_color
  local success_pipeline_str=""
  while [ $success_pipeline_count -ne $total_pipeline_count ]; do
    # 清空
    log_buf=""
    for project_pipeline_id in "${project_pipeline_id_arr[@]}"; do
      project_id=$(echo "$project_pipeline_id" | cut -d# -f1)
      pipeline_ids=$(echo "$project_pipeline_id" | cut -d# -f2)
      IFS="," read -r -a pipeline_id_arr <<< "$pipeline_ids"
      for pipeline_id in "${pipeline_id_arr[@]}"; do
        get_pipeline_status "$project_id" "$pipeline_id"
        web_url="$(echo "$pipeline_status_json" | jq -r .web_url)"
        status="$(echo "$pipeline_status_json" | jq -r .status)"
        case $status in
        "$R_PIPELINE_STATUS_PENDING")
          status_color="$R_COLOR_Y"
        ;;
        "$R_PIPELINE_STATUS_RUNNING")
          status_color="$R_COLOR_G"
          ;;
        "$R_PIPELINE_STATUS_SUCCESS")
          if ! echo ",${success_pipeline_str}," | grep -q ",${pipeline_id},"; then
            success_pipeline_count=$((success_pipeline_count+1))
            success_pipeline_str="${success_pipeline_str},${pipeline_id}"
          fi
          status_color="$R_COLOR_G"
          ;;
        "$R_PIPELINE_STATUS_FAILED" | "$R_PIPELINE_STATUS_CANCELED")
          ## 如果Pipeline失败或者取消, 设置错误标志
          pipeline_has_failure="true"
          status_color="$R_COLOR_R"
          ;;
        esac
        log_buf="[${status_color}${status}${R_RESET}]${web_url} $log_buf"
      done
    done

    if [ $success_pipeline_count -eq "$total_pipeline_count" ]; then
      ## 不要加\r, 避免看不到最终结果
      echo -ne "Status[$success_pipeline_count/$total_pipeline_count]: ${log_buf}\n"
    else
      if [ "$pipeline_has_failure" == "true" ]; then
        ## 不要加\r, 避免看不到哪个Pipeline失败了
        echo -ne "Status[$success_pipeline_count/$total_pipeline_count]: ${log_buf}\n"
        error_log "存在失败或取消的Pipeline, 打包异常终止, 请检查Pipeline状态"
      else
        if [ -n "$CI_PROJECT_ID" ]; then
          # CI环境下, \r输出不了, 采用常规的滚动输出(在命令行下, 采用覆盖式输出)
          echo -e "Status[$success_pipeline_count/$total_pipeline_count]: ${log_buf}"
        else
          clear_console
          echo -ne "Status[$success_pipeline_count/$total_pipeline_count]: ${log_buf}\r"
        fi
        sleep "$check_interval"
      fi
    fi
  done
}