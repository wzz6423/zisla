.PHONY: run stop update build-package sync-cask clean

LOCAL_SIGNING_ENV := SIGNING_MODE=dev

ifeq ($(OS),Windows_NT)
PLATFORM := windows
else
UNAME_S := $(shell uname -s 2>/dev/null)
ifeq ($(UNAME_S),Darwin)
PLATFORM := macos
else
PLATFORM := unsupported
endif
endif

ifeq ($(PLATFORM),macos)

run:
	@$(LOCAL_SIGNING_ENV) mac/Scripts/dev-service.sh run

stop:
	@mac/Scripts/dev-service.sh stop

build-package:
	@mac/Scripts/build-package.sh

# VERSION is required. Add PUBLISH_TAP=true to push the cask to the Homebrew tap.
sync-cask:
	@mac/Scripts/sync-homebrew-cask.sh

clean: stop
	@rm -rf outputs .impeccable .playwright-cli \
		mac/dist mac/.build mac/.swiftpm mac/DerivedData mac/.release-* \
		web/dist web/.playwright web/screenshots
else ifeq ($(PLATFORM),windows)

WINDOWS_POWERSHELL ?= powershell.exe

run:
	@$(WINDOWS_POWERSHELL) -NoProfile -ExecutionPolicy Bypass -Command "$$ErrorActionPreference = 'Stop'; $$platform = if ($$env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'ARM64' } else { 'x64' }; $$vswhere = Join-Path $${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'; if (Test-Path $$vswhere) { $$msbuild = & $$vswhere -latest -products * -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1 }; if (-not $$msbuild) { $$command = Get-Command MSBuild.exe -ErrorAction SilentlyContinue; if ($$command) { $$msbuild = $$command.Source } }; if (-not $$msbuild -or -not (Test-Path $$msbuild)) { throw '未找到 Visual Studio MSBuild。请安装 Visual Studio 的 C++ 桌面开发和 WinUI 应用开发工作负载。' }; & $$msbuild 'windows\Zisla.Windows.sln' /restore /m /p:Configuration=Debug /p:Platform=$$platform; if ($$LASTEXITCODE -ne 0) { exit $$LASTEXITCODE }; $$app = Join-Path (Get-Location) ('windows\bin\' + $$platform + '\Debug\Zisla.exe'); if (-not (Test-Path $$app)) { throw ('构建完成但未找到 ' + $$app) }; Start-Process -FilePath $$app"

stop:
	@$(WINDOWS_POWERSHELL) -NoProfile -Command "Write-Host 'Windows 版本由系统管理，无需停止调试服务。'"

else

run stop:
	@echo "错误：当前平台 $(UNAME_S) 不受支持。仅支持 macOS 和 Windows。" >&2; exit 2

endif

update: run
