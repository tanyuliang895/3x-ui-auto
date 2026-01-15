#!/bin/bash
# ... 前面的 BBR、依赖、开放80、下载部分不变 ...

TEMP_SCRIPT="/tmp/3x-ui-install.sh"
curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh -o "$TEMP_SCRIPT"

if [ ! -s "$TEMP_SCRIPT" ]; then
    echo -e "\033[31m下载失败\033[0m"
    exit 1
fi

chmod +x "$TEMP_SCRIPT"

echo "TEMP_SCRIPT path: $TEMP_SCRIPT"
ls -l "$TEMP_SCRIPT" || echo "文件不存在！"

echo "开始自动化安装..."

expect <<'END_EXPECT'
    set timeout 120
    log_user 1

    send_user "Debug: Inside expect, TEMP_SCRIPT env = $env(TEMP_SCRIPT)\n"

    spawn bash /tmp/3x-ui-install.sh   ;# 硬编码路径，避免任何变量问题

    # 端口 [y/n]
    expect {
        "Would you like to customize the Panel Port settings? (If not, a random port will be applied) [y/n]: " { send "y\r" }
        timeout { send_user "TIMEOUT at [y/n]\n"; exit 1 }
        eof { send_user "EOF early\n"; exit 1 }
    }

    # 端口输入
    expect {
        "Please set up the panel port: " { send "2026\r" }   ;# 硬编码你的端口，避免 env 坑
        timeout { send_user "TIMEOUT at port input\n"; exit 1 }
    }

    # SSL
    expect {
        "Choose an option (default 2 for IP): " { send "\r" }
        "Choose SSL certificate setup method:" { send "2\r" }
        timeout { send_user "TIMEOUT at SSL\n"; exit 1 }
    }

    # IPv6
    expect {
        "Do you have an IPv6 address to include? (leave empty to skip): " { send "\r" }
        timeout { }
    }

    # ACME 端口处理（简化版，尝试 80 -> 81 -> 82）
    expect {
        "Port to use for ACME HTTP-01 listener (default 80): " { send "80\r" }
        -re "Port .* is in use." { send "81\r" }
        -re "Enter another port.*: " { send "81\r" }
        timeout { }
    }
    expect {
        -re "Port .* is in use." { send "82\r" }
        timeout { }
    }

    # 兜底
    expect eof
END_EXPECT

# 清理 + 设置用户名密码部分不变...
rm -f "$TEMP_SCRIPT"

# ... 你的等待循环和 restart ...
