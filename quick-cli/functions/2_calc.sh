## 计算选项, 并设置变量值
## ret_long_options: 长选项字符串
## ret_short_options: 短选项字符串
## ret_long_option_arr: 长选项数组
## ret_description_var_str: 描述变量的定义串
## dyn_short_option_<long_option>: 动态变量, 长选项对应的短选项, 如果没有对应的短选项, 则该变量对应的值是空的
## dyn_var_name_<long_option>: 动态变量, 长选项对应的变量名称
## dyn_option_type_<long_option>: 动态变量, 长选项对应的选项类型
calc_options() {
  # 方法返回值
  ret_long_options=""
  ret_short_options=""
  ret_long_option_arr=
  ret_description_var_str=""
  local ret_description_var_snippet

  local long_option_arr_str=""

  pushd . > /dev/null
  cd "$tool_name/options" || exit 1
  local long_option
  local short_option
  local var_name
  local type
  local default
  local default_value=""
  local description

  # 取值为"",":","::"
  local option_sign

  for option_file in *.yaml; do
    long_option=$(yq e ".long" "$option_file")
    [ "$long_option" == "null" ] || [ -z "$long_option" ] && long_option="${option_file%.yaml}"
    long_option_arr_str=$(append "$long_option_arr_str" "$long_option")

    short_option=$(yq e ".short" "$option_file")

    type=$(yq e ".type" "$option_file")
    [ "$type" == "null" ] && type="$R_OPTION_TYPE_VALUE"
    # 创建动态变量
    create_option_type_dynamic_var "$long_option" "$type"

    var_name=$(yq e ".var_name" "$option_file")
    [ "$var_name" == "null" ] || [ -z "$var_name" ] && var_name="${long_option//-/_}"
    # 创建动态变量
    create_var_name_dynamic_var "$long_option" "$var_name"

    description=$(yq e ".description" "$option_file")
    [ "$description" == "null" ] && description=""
    create_option_description_dynamic_var "$long_option" "$description"

    ret_description_var_snippet=$(printf "# shellcheck disable=SC2034\n%s" "readonly R_PARAM_$(echo "${long_option^^}" | tr '-' '_')_DESCRIPTION=\"$description\"")
    if [ -n "$ret_description_var_str" ]; then
      ret_description_var_str=$(printf "%s\n%s" "$ret_description_var_str" "$ret_description_var_snippet")
    else
      ret_description_var_str="$ret_description_var_snippet"
    fi

    case "$type" in
    "$R_OPTION_TYPE_FLAG")
      option_sign=""
      default_value="false"
      ;;
    "$R_OPTION_TYPE_VALUE")
      option_sign=":"
      ;;
    "$R_OPTION_TYPE_VALUE_OPT")
      option_sign="::"
      ;;
    esac

    default=$(yq e ".default" "$option_file")
    [ "$default" == "null" ] || [ -z "$default" ] && default="$default_value"
    # 创建动态变量
    create_option_default_dynamic_var "$long_option" "$default"

    ret_long_options="$(append "$ret_long_options" "${long_option}${option_sign}")"
    if [ "$short_option" != "null" ] && [ -n "$short_option" ]; then
      ret_short_options="$(append "$ret_short_options" "${short_option}${option_sign}")"
      # 创建动态变量
      create_short_option_dynamic_var "$long_option" "$short_option"
    fi
  done
  popd > /dev/null || exit 1

  # 设置返回值<ret_long_option_arr>
  IFS="," read -r -a ret_long_option_arr <<< "$long_option_arr_str"
}

## 计算循环解析位置参数的代码(case部分), 变量值被保存在<ret_loop_code>变量中
calc_resolve_loop() {
  ret_loop_code=""
  local long_option
  local short_option
  local var_name
  local default
  local case_str
  local case_statement
  local case_blob
  local option_type
  for long_option in "${ret_long_option_arr[@]}"; do
    case_str="\"--$long_option\""
    short_option=$(get_short_option_dynamic_var "$long_option")
    [ -n "$short_option" ] && case_str="${case_str} | \"-${short_option}\""
    var_name=$(get_var_name_dynamic_var "$long_option")

    option_type=$(get_option_type_dynamic_var "$long_option")
    case "$option_type" in
    "$R_OPTION_TYPE_FLAG")
      case_statement=$(printf "%s\n    %s" "$var_name=true" "shift 1")
      ;;
    "$R_OPTION_TYPE_VALUE_OPT")
      default=$(get_option_default_dynamic_var "$long_option")
      case_statement=$(printf "case \"\$2\" in\n    \"\")\n      %s=\"%s\"\n      ;;\n    *)\n      %s=\"\$2\"\n      ;;\n    esac\n    shift 2" \
        "$var_name" "$default" "$var_name")
      ;;
    "$R_OPTION_TYPE_VALUE")
      case_statement=$(printf "%s\n    %s" "$var_name=\"\$2\"" "shift 2")
      ;;
    *)
      error_log "不支持的type: $option_type, 可选的类型有: $R_OPTION_TYPE_VALUE_OPT,$R_OPTION_TYPE_VALUE,$R_OPTION_TYPE_FLAG, Option: $long_option"
      ;;
    esac

    case_blob=$(printf "  %s)\n    %s\n    ;;" "$case_str" "$case_statement")
    if [ -n "$ret_loop_code" ]; then
      ret_loop_code=$(printf "%s\n%s" "$ret_loop_code" "$case_blob")
    else
      ret_loop_code="$case_blob"
    fi
  done
}

## 计算Action, 并设置变量值
## ret_actions_str: Action方法字符串
## ret_actions_params_check_str: Action参数校验方法字符串
## ret_help_action_str: help方法字符串
calc_actions_str() {
  ret_actions_str=""
  ret_actions_params_check_str=""
  ret_help_action_str=""

  local ret_actions_params_check_snippet

  pushd . > /dev/null
  cd "$tool_name/actions" || exit 1
  local action_shell_file
  local action_content
  local action
  local check_body
  local options_str
  local options
  local required_str
  local required
  local idx

  tool_actions="help"

  local -r help_snippet_tool_name="printf \"%s\n  %s\n\n\" \"名称:\" \"$tool_name\""
  local -r help_snippet_tool_version="printf \"%s\n  %s\n\n\" \"版本:\" \"$tool_version\""
  local help_snippet_action_detail
  local help_snippet_action_detail_snippet
  local description
  local use_example

  for action_file in *.yaml; do
    action="${action_file%.yaml}"

    tool_actions=$(append "$tool_actions" "$action")

    description=$(yq e ".description" "$action_file")
    [ "$description" == "null" ] || [ -z "$description" ] && description="$action"

    use_example=$(yq e ".use_example" "$action_file")
    [ "$use_example" == "null" ] && use_example=""

    action_shell_file=$(yq e ".file" "$action_file")
    [ "$action_shell_file" == "null" ] || [ -z "$action_shell_file" ] && action_shell_file="${action_file%.yaml}.sh"
    [ ! -f "$action_shell_file" ] && error_log "${action_file}指定的shell文件不存在: $action_shell_file"``
    action_content=$(cat "$action_shell_file")
    # 加action_前缀
    action_content="${R_ACTION_PREFIX}${action_content}"
    if [ -n "$ret_actions_str" ]; then
      ret_actions_str=$(printf "%s\n\n%s" "$ret_actions_str" "$action_content")
    else
      ret_actions_str="$action_content"
    fi

    idx=0
    required_str=""
    while true; do
      required=$(yq e ".required[$idx]" "$action_file")
      [ "$required" == "null" ] && break
      required_str=$(append "$required_str" "$required" " ")
      idx=$((idx+1))
    done

    idx=0
    options_str=""
    while true; do
      options=$(yq e ".options[$idx]" "$action_file")
      [ "$options" == "null" ] && break
      options_str=$(append "$options_str" "$options" " ")
      idx=$((idx+1))
    done

    check_body=$(printf "  options_str=\"%s\"\n  check_action_param %s %s" "$options_str" "$action" "$required_str")
    # 构建检查方法字符串
    ret_actions_params_check_snippet=$(printf "%s() {\n%s\n}" "${R_ACTION_PARAMS_CHECK_PREFIX}${action//-/_}" "$check_body")
    if [ -n "$ret_actions_params_check_str" ]; then
      ret_actions_params_check_str=$(printf "%s\n\n%s" "$ret_actions_params_check_str" "$ret_actions_params_check_snippet")
    else
      ret_actions_params_check_str="$ret_actions_params_check_snippet"
    fi

    help_snippet_action_detail_snippet="  explain_action \"$action\" \"$description\" \"$use_example\""
    if [ -n "$help_snippet_action_detail" ]; then
      help_snippet_action_detail=$(printf "%s\n%s" "$help_snippet_action_detail" "$help_snippet_action_detail_snippet")
    else
      help_snippet_action_detail="$help_snippet_action_detail_snippet"
    fi
  done

  local -r help_snippet_tool_actions="printf \"%s\n  %s\n\n\" \"Actions:\" \"$tool_actions\""
  ret_help_action_str=$(printf "action_help() {\n  %s\n  %s\n  %s\n%s\n}" "$help_snippet_tool_name" "$help_snippet_tool_version" \
    "$help_snippet_tool_actions" "$help_snippet_action_detail")
  popd > /dev/null || exit 1
}

## 计算Function, 并设置变量值
## ret_functions_str
calc_functions_str() {
  ret_functions_str=""
  local ret_functions_str_snippet
  pushd . > /dev/null
  cd "$tool_name/functions" || return
  for function_file in *.sh; do
    ret_functions_str_snippet=$(cat "$function_file")
    if [ -n "$ret_functions_str" ]; then
      ret_functions_str=$(printf "%s\n\n%s" "$ret_functions_str" "$ret_functions_str_snippet")
    else
      ret_functions_str="$ret_functions_str_snippet"
    fi
  done
  popd > /dev/null || exit 1
}

## 计算Variables, 并设置变量值
## ret_variables_str
calc_variables_str() {
  ret_variables_str=""
  local ret_variables_str_snippet
  pushd . > /dev/null
  cd "$tool_name/variables" || return
  for variable_file in *.sh; do
    ret_variables_str_snippet=$(cat "$variable_file")
    if [ -n "$ret_variables_str" ]; then
      ret_variables_str=$(printf "%s\n\n%s" "$ret_variables_str" "$ret_variables_str_snippet")
    else
      ret_variables_str="$ret_variables_str_snippet"
    fi
  done
  popd > /dev/null || exit 1
}
