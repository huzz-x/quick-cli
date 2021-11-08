## 创建短选项的动态变量
# $1: Long Option
# $2: Value
create_short_option_dynamic_var() {
  local -r long_option="$1"
  local -r value="$2"
  local -r name="dyn_short_option_${long_option//-/_}"
  create_dynamic_var "$name" "$value"
}
## 获取短选项的动态变量
# $1: Long Option
get_short_option_dynamic_var() {
  local -r long_option="$1"
  local -r name="dyn_short_option_${long_option//-/_}"
  get_dynamic_var "$name"
}

## 创建变量名称(var_name)的动态变量
# $1: Long Option
# $2: Value
create_var_name_dynamic_var() {
  local -r long_option="$1"
  local -r value="$2"
  local -r name="dyn_var_name_${long_option//-/_}"
  create_dynamic_var "$name" "$value"
}
## 获取变量名称(var_name)的动态变量
# $1: Long Option
get_var_name_dynamic_var() {
  local -r long_option="$1"
  local -r name="dyn_var_name_${long_option//-/_}"
  get_dynamic_var "$name"
}

## 创建选项类别的动态变量
# $1: Long Option
# $2: Value
create_option_type_dynamic_var() {
  local -r long_option="$1"
  local -r value="$2"
  local -r name="dyn_option_type_${long_option//-/_}"
  create_dynamic_var "$name" "$value"
}
## 获取选项类别的动态变量
# $1: Long Option
get_option_type_dynamic_var() {
  local -r long_option="$1"
  local -r name="dyn_option_type_${long_option//-/_}"
  get_dynamic_var "$name"
}

## 创建选项默认值的动态变量
# $1: Long Option
# $2: Value
create_option_default_dynamic_var() {
  local -r long_option="$1"
  local -r value="$2"
  local -r name="dyn_option_default_${long_option//-/_}"
  create_dynamic_var "$name" "$value"
}
## 获取选项默认值的动态变量
# $1: Long Option
get_option_default_dynamic_var() {
  local -r long_option="$1"
  local -r name="dyn_option_default_${long_option//-/_}"
  get_dynamic_var "$name"
}

## 创建选项描述的动态变量
# $1: Long Option
# $2: Value
create_option_description_dynamic_var() {
  local -r long_option="$1"
  local -r value="$2"
  local -r name="dyn_option_description${long_option//-/_}"
  create_dynamic_var "$name" "$value"
}
## 获取选项描述的动态变量
# $1: Long Option
get_option_description_dynamic_var() {
  local -r long_option="$1"
  local -r name="dyn_option_description_${long_option//-/_}"
  get_dynamic_var "$name"
}