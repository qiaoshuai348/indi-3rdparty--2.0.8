#!/usr/bin/env bash
set -euo pipefail

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-7624}"
DEVICE="${DEVICE:-QHY Mount}"
SERVER_LOG="${SERVER_LOG:-/tmp/indi_qhy_mount_server.log}"
RESULT_LOG="${RESULT_LOG:-/tmp/indi_qhy_mount_result.log}"
DRIVER_BIN="${DRIVER_BIN:-indi_qhy_mount}"
LOCAL_SOCKET="${LOCAL_SOCKET:-/tmp/indiserver_qhy_mount_test}"

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "缺少命令: $1"
        exit 1
    }
}

need_cmd indiserver
need_cmd indi_getprop
need_cmd indi_setprop
need_cmd "${DRIVER_BIN}"

SERVER_PID=""
cleanup() {
    if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" 2>/dev/null; then
        kill "${SERVER_PID}" 2>/dev/null || true
        wait "${SERVER_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

start_server() {
    : > "${SERVER_LOG}"
    indiserver -v -u "${LOCAL_SOCKET}" -p "${PORT}" "${DRIVER_BIN}" >"${SERVER_LOG}" 2>&1 &
    SERVER_PID=$!
}

wait_server_ready() {
    local i
    for i in $(seq 1 30); do
        if indi_getprop -h "${HOST}" -p "${PORT}" "${DEVICE}.CONNECTION.*" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.5
    done
    return 1
}

get_prop() {
    indi_getprop -h "${HOST}" -p "${PORT}" "$1" 2>/dev/null || true
}

set_prop() {
    indi_setprop -h "${HOST}" -p "${PORT}" "$1" >/dev/null
}

wait_connect_state() {
    local want="$1"
    local i out
    for i in $(seq 1 20); do
        out="$(get_prop "${DEVICE}.CONNECTION.CONNECT")"
        if [[ "${want}" == "On" ]] && [[ "${out}" == *"=On"* ]]; then
            return 0
        fi
        if [[ "${want}" == "Off" ]] && [[ "${out}" == *"=Off"* ]]; then
            return 0
        fi
        sleep 0.5
    done
    return 1
}

run_case() {
    local sim_mode="$1"
    local title="$2"
    local ok=1

    echo "================ ${title} ================"
    echo "SIMULATION=${sim_mode}"

    if [[ "${sim_mode}" == "On" ]]; then
        set_prop "${DEVICE}.SIMULATION.ENABLE=On" || true
    else
        set_prop "${DEVICE}.SIMULATION.DISABLE=On" || true
    fi

    echo "-- 当前关键属性 --"
    get_prop "${DEVICE}.SIMULATION.*"
    get_prop "${DEVICE}.DEVICE_PORT.*"
    get_prop "${DEVICE}.CONNECTION.*"

    echo "-- 发起连接 --"
    if set_prop "${DEVICE}.CONNECTION.CONNECT=On"; then
        if wait_connect_state "On"; then
            ok=0
            echo "连接结果: 成功"
        else
            echo "连接结果: 失败（超时，CONNECT 未变为 On）"
        fi
    else
        echo "连接结果: 失败（发送 CONNECT 命令失败）"
    fi

    echo "-- 连接后属性 --"
    get_prop "${DEVICE}.CONNECTION.*"
    get_prop "${DEVICE}.DRIVER_INFO.*"

    echo "-- 断开连接 --"
    set_prop "${DEVICE}.CONNECTION.DISCONNECT=On" || true
    wait_connect_state "Off" || true
    get_prop "${DEVICE}.CONNECTION.*"

    echo
    return "${ok}"
}

{
    echo "QHY Mount INDI 连接诊断"
    echo "HOST=${HOST} PORT=${PORT} DEVICE=${DEVICE}"
    echo "server log: ${SERVER_LOG}"
    echo
} | tee "${RESULT_LOG}"

start_server
if ! wait_server_ready; then
    echo "indiserver/driver 启动失败，请检查: ${SERVER_LOG}" | tee -a "${RESULT_LOG}"
    exit 2
fi

{
    if run_case "On" "场景A: 模拟模式连接测试"; then
        A_RET=0
    else
        A_RET=1
    fi

    if run_case "Off" "场景B: 实机模式连接测试（默认串口）"; then
        B_RET=0
    else
        B_RET=1
    fi

    echo "================ 诊断结论 ================"
    if [[ ${A_RET} -eq 0 && ${B_RET} -eq 1 ]]; then
        echo "驱动本身可连接（模拟模式正常），实机模式失败通常是串口路径/权限/波特率问题。"
    elif [[ ${A_RET} -eq 0 && ${B_RET} -eq 0 ]]; then
        echo "模拟与实机都可连接，问题更可能出在 KStars 端配置流程。"
    else
        echo "模拟模式都失败，优先检查驱动逻辑或运行环境。"
    fi
    echo "请同时查看详细日志: ${SERVER_LOG}"
} | tee -a "${RESULT_LOG}"

