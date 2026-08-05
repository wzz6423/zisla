if(WIN32)
    set(ZISLA_FILE_REPLACEMENT_SOURCE src/FileReplacementWindows.cpp)
else()
    set(ZISLA_FILE_REPLACEMENT_SOURCE src/FileReplacementPortable.cpp)
endif()

add_library(zisla_windows_core STATIC
    src/Alarm.cpp
    src/AIActivityMerger.cpp
    src/AIActivityPresentation.cpp
    src/AIAgentCLIRelay.cpp
    src/AIAgentChatProtocols.cpp
    src/AIAgentChatRequestPlanner.cpp
    src/AIAgentRouting.cpp
    src/AIAgentRoutingRepository.cpp
    src/AIAgentServiceResponses.cpp
    src/AIAgentSkills.cpp
    src/AIAgentWorkspace.cpp
    src/AIAgentWorkspaceRepository.cpp
    src/OpenAIChatCompletions.cpp
    src/OpenCodeSessionScanner.cpp
    src/AIModels.cpp
    src/AIStateRepository.cpp
    src/BrowserDownloads.cpp
    src/Calendar.cpp
    src/CLIApplication.cpp
    src/CLIParser.cpp
    src/CameraMirror.cpp
    src/ClaudeActivityParser.cpp
    src/ClaudeSessionScanner.cpp
    src/CopilotSessionScanner.cpp
    src/GeminiSessionScanner.cpp
    src/GrokSessionScanner.cpp
    src/HarnessSessionScanner.cpp
    src/KimiSessionScanner.cpp
    src/QoderSessionScanner.cpp
    src/QwenSessionScanner.cpp
    src/TraeSessionScanner.cpp
    src/WorkBuddySessionScanner.cpp
    src/CleaningSession.cpp
    src/ClipboardHistory.cpp
    src/ClipboardLinkDetector.cpp
    src/CodexActivityParser.cpp
    src/CodexSessionScanner.cpp
    src/DashboardPresentation.cpp
    src/DiskCleanup.cpp
    src/DesktopTools.cpp
    src/Download.cpp
    src/DoubaoSessionScanner.cpp
    src/FileShelfRepository.cpp
    ${ZISLA_FILE_REPLACEMENT_SOURCE}
    src/OverlayPlacementEngine.cpp
    src/PDFProcessing.cpp
    src/Pet.cpp
    src/Pomodoro.cpp
    src/PowerRequests.cpp
    src/PresentationEngine.cpp
    src/QuickNotes.cpp
    src/SideNoticeQueue.cpp
    src/SystemMonitor.cpp
    src/Teleprompter.cpp
    src/VoiceInput.cpp
    src/VoiceHotkey.cpp
    src/ModuleCatalog.cpp
    src/Mail.cpp
    src/CompactStatusSelector.cpp
    src/NowPlaying.cpp
    src/Update.cpp
    src/Weather.cpp
)

target_compile_features(zisla_windows_core PUBLIC cxx_std_20)
target_include_directories(zisla_windows_core
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)
target_link_libraries(zisla_windows_core PRIVATE zisla_sqlite zisla_yyjson)

if(MSVC)
    target_compile_options(zisla_windows_core PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_core PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()
