add_executable(zisla_windows_core_tests CoreTests.cpp)
target_link_libraries(zisla_windows_core_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_core_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_core_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_core_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(NAME zisla_windows_core_tests COMMAND zisla_windows_core_tests)

add_executable(zisla_windows_ai_agent_cli_relay_tests AIAgentCLIRelayTests.cpp)
target_link_libraries(zisla_windows_ai_agent_cli_relay_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_ai_agent_cli_relay_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_ai_agent_cli_relay_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(
        zisla_windows_ai_agent_cli_relay_tests
        PRIVATE
            -Wall
            -Wextra
            -Wpedantic
            -Werror
    )
endif()

add_test(
    NAME zisla_windows_ai_agent_cli_relay_tests
    COMMAND zisla_windows_ai_agent_cli_relay_tests
)

add_executable(zisla_windows_alarm_tests AlarmTests.cpp)
target_link_libraries(
    zisla_windows_alarm_tests
    PRIVATE
        zisla_windows_core
        zisla_sqlite
)
target_compile_features(zisla_windows_alarm_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_alarm_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_alarm_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(NAME zisla_windows_alarm_tests COMMAND zisla_windows_alarm_tests)

add_executable(zisla_windows_feature_tests FeatureTests.cpp)
target_link_libraries(zisla_windows_feature_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_feature_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_feature_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_feature_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(NAME zisla_windows_feature_tests COMMAND zisla_windows_feature_tests)

add_executable(zisla_windows_codex_activity_tests CodexActivityParserTests.cpp)
target_link_libraries(zisla_windows_codex_activity_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_codex_activity_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_codex_activity_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_codex_activity_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(NAME zisla_windows_codex_activity_tests COMMAND zisla_windows_codex_activity_tests)

add_executable(zisla_windows_claude_activity_tests ClaudeActivityParserTests.cpp)
target_link_libraries(zisla_windows_claude_activity_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_claude_activity_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_claude_activity_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_claude_activity_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(NAME zisla_windows_claude_activity_tests COMMAND zisla_windows_claude_activity_tests)

add_executable(zisla_windows_codex_session_scanner_tests CodexSessionScannerTests.cpp)
target_link_libraries(zisla_windows_codex_session_scanner_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_codex_session_scanner_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_codex_session_scanner_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_codex_session_scanner_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_codex_session_scanner_tests
    COMMAND zisla_windows_codex_session_scanner_tests
)

add_executable(zisla_windows_claude_session_scanner_tests ClaudeSessionScannerTests.cpp)
target_link_libraries(zisla_windows_claude_session_scanner_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_claude_session_scanner_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_claude_session_scanner_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_claude_session_scanner_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_claude_session_scanner_tests
    COMMAND zisla_windows_claude_session_scanner_tests
)

add_executable(zisla_windows_gemini_session_scanner_tests GeminiSessionScannerTests.cpp)
target_link_libraries(zisla_windows_gemini_session_scanner_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_gemini_session_scanner_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_gemini_session_scanner_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_gemini_session_scanner_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_gemini_session_scanner_tests
    COMMAND zisla_windows_gemini_session_scanner_tests
)

add_executable(zisla_windows_kimi_session_scanner_tests KimiSessionScannerTests.cpp)
target_link_libraries(zisla_windows_kimi_session_scanner_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_kimi_session_scanner_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_kimi_session_scanner_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_kimi_session_scanner_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_kimi_session_scanner_tests
    COMMAND zisla_windows_kimi_session_scanner_tests
)

add_executable(zisla_windows_qwen_session_scanner_tests QwenSessionScannerTests.cpp)
target_link_libraries(zisla_windows_qwen_session_scanner_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_qwen_session_scanner_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_qwen_session_scanner_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_qwen_session_scanner_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_qwen_session_scanner_tests
    COMMAND zisla_windows_qwen_session_scanner_tests
)

add_executable(zisla_windows_grok_session_scanner_tests GrokSessionScannerTests.cpp)
target_link_libraries(zisla_windows_grok_session_scanner_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_grok_session_scanner_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_grok_session_scanner_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_grok_session_scanner_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_grok_session_scanner_tests
    COMMAND zisla_windows_grok_session_scanner_tests
)

add_executable(zisla_windows_harness_session_scanner_tests HarnessSessionScannerTests.cpp)
target_link_libraries(zisla_windows_harness_session_scanner_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_harness_session_scanner_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_harness_session_scanner_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_harness_session_scanner_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_harness_session_scanner_tests
    COMMAND zisla_windows_harness_session_scanner_tests
)

add_executable(zisla_windows_workbuddy_session_scanner_tests WorkBuddySessionScannerTests.cpp)
target_link_libraries(zisla_windows_workbuddy_session_scanner_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_workbuddy_session_scanner_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_workbuddy_session_scanner_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_workbuddy_session_scanner_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_workbuddy_session_scanner_tests
    COMMAND zisla_windows_workbuddy_session_scanner_tests
)

add_executable(zisla_windows_copilot_session_scanner_tests CopilotSessionScannerTests.cpp)
target_link_libraries(zisla_windows_copilot_session_scanner_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_copilot_session_scanner_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_copilot_session_scanner_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_copilot_session_scanner_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_copilot_session_scanner_tests
    COMMAND zisla_windows_copilot_session_scanner_tests
)

add_executable(zisla_windows_qoder_session_scanner_tests QoderSessionScannerTests.cpp)
target_link_libraries(zisla_windows_qoder_session_scanner_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_qoder_session_scanner_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_qoder_session_scanner_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_qoder_session_scanner_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_qoder_session_scanner_tests
    COMMAND zisla_windows_qoder_session_scanner_tests
)

add_executable(zisla_windows_doubao_session_scanner_tests DoubaoSessionScannerTests.cpp)
target_link_libraries(zisla_windows_doubao_session_scanner_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_doubao_session_scanner_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_doubao_session_scanner_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_doubao_session_scanner_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_doubao_session_scanner_tests
    COMMAND zisla_windows_doubao_session_scanner_tests
)

add_executable(zisla_windows_opencode_session_scanner_tests OpenCodeSessionScannerTests.cpp)
target_link_libraries(
    zisla_windows_opencode_session_scanner_tests
    PRIVATE
        zisla_windows_core
        zisla_sqlite
)
target_compile_features(zisla_windows_opencode_session_scanner_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_opencode_session_scanner_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_opencode_session_scanner_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_opencode_session_scanner_tests
    COMMAND zisla_windows_opencode_session_scanner_tests
)

add_executable(zisla_windows_trae_session_scanner_tests TraeSessionScannerTests.cpp)
target_link_libraries(zisla_windows_trae_session_scanner_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_trae_session_scanner_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_trae_session_scanner_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_trae_session_scanner_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_trae_session_scanner_tests
    COMMAND zisla_windows_trae_session_scanner_tests
)

add_executable(zisla_windows_ai_activity_presentation_tests AIActivityPresentationTests.cpp)
target_link_libraries(zisla_windows_ai_activity_presentation_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_ai_activity_presentation_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_ai_activity_presentation_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_ai_activity_presentation_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_ai_activity_presentation_tests
    COMMAND zisla_windows_ai_activity_presentation_tests
)

add_executable(zisla_windows_ai_state_repository_tests AIStateRepositoryTests.cpp)
target_link_libraries(
    zisla_windows_ai_state_repository_tests
    PRIVATE
        zisla_windows_core
        zisla_sqlite
)
target_compile_features(zisla_windows_ai_state_repository_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_ai_state_repository_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_ai_state_repository_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_ai_state_repository_tests
    COMMAND zisla_windows_ai_state_repository_tests
)

add_executable(zisla_windows_ai_agent_routing_tests AIAgentRoutingTests.cpp)
target_link_libraries(zisla_windows_ai_agent_routing_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_ai_agent_routing_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_ai_agent_routing_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_ai_agent_routing_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_ai_agent_routing_tests
    COMMAND zisla_windows_ai_agent_routing_tests
)

add_executable(
    zisla_windows_ai_agent_routing_repository_tests
    AIAgentRoutingRepositoryTests.cpp
)
target_link_libraries(
    zisla_windows_ai_agent_routing_repository_tests
    PRIVATE
        zisla_windows_core
        zisla_sqlite
)
target_compile_features(zisla_windows_ai_agent_routing_repository_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_ai_agent_routing_repository_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_ai_agent_routing_repository_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_ai_agent_routing_repository_tests
    COMMAND zisla_windows_ai_agent_routing_repository_tests
)

add_executable(zisla_windows_ai_agent_skills_tests AIAgentSkillsTests.cpp)
target_link_libraries(zisla_windows_ai_agent_skills_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_ai_agent_skills_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_ai_agent_skills_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_ai_agent_skills_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_ai_agent_skills_tests
    COMMAND zisla_windows_ai_agent_skills_tests
)

add_executable(zisla_windows_ai_agent_workspace_tests AIAgentWorkspaceTests.cpp)
target_link_libraries(zisla_windows_ai_agent_workspace_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_ai_agent_workspace_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_ai_agent_workspace_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_ai_agent_workspace_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_ai_agent_workspace_tests
    COMMAND zisla_windows_ai_agent_workspace_tests
)

add_executable(
    zisla_windows_openai_chat_completions_tests
    OpenAIChatCompletionsTests.cpp
)
target_link_libraries(
    zisla_windows_openai_chat_completions_tests
    PRIVATE
        zisla_windows_core
)
target_compile_features(zisla_windows_openai_chat_completions_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(
        zisla_windows_openai_chat_completions_tests
        PRIVATE
            /W4 /WX /permissive- /utf-8
    )
else()
    target_compile_options(
        zisla_windows_openai_chat_completions_tests
        PRIVATE
            -Wall -Wextra -Wpedantic -Werror
    )
endif()

add_test(
    NAME zisla_windows_openai_chat_completions_tests
    COMMAND zisla_windows_openai_chat_completions_tests
)

add_executable(
    zisla_windows_ai_agent_chat_protocols_tests
    AIAgentChatProtocolsTests.cpp
)
target_link_libraries(
    zisla_windows_ai_agent_chat_protocols_tests
    PRIVATE
        zisla_windows_core
)
target_compile_features(
    zisla_windows_ai_agent_chat_protocols_tests
    PRIVATE
        cxx_std_20
)

if(MSVC)
    target_compile_options(
        zisla_windows_ai_agent_chat_protocols_tests
        PRIVATE
            /W4 /WX /permissive- /utf-8
    )
else()
    target_compile_options(
        zisla_windows_ai_agent_chat_protocols_tests
        PRIVATE
            -Wall -Wextra -Wpedantic -Werror
    )
endif()

add_test(
    NAME zisla_windows_ai_agent_chat_protocols_tests
    COMMAND zisla_windows_ai_agent_chat_protocols_tests
)

add_executable(
    zisla_windows_ai_agent_service_responses_tests
    AIAgentServiceResponsesTests.cpp
)
target_link_libraries(
    zisla_windows_ai_agent_service_responses_tests
    PRIVATE
        zisla_windows_core
)
target_compile_features(
    zisla_windows_ai_agent_service_responses_tests
    PRIVATE
        cxx_std_20
)

if(MSVC)
    target_compile_options(
        zisla_windows_ai_agent_service_responses_tests
        PRIVATE
            /W4 /WX /permissive- /utf-8
    )
else()
    target_compile_options(
        zisla_windows_ai_agent_service_responses_tests
        PRIVATE
            -Wall -Wextra -Wpedantic -Werror
    )
endif()

add_test(
    NAME zisla_windows_ai_agent_service_responses_tests
    COMMAND zisla_windows_ai_agent_service_responses_tests
)

add_executable(
    zisla_windows_ai_agent_chat_request_planner_tests
    AIAgentChatRequestPlannerTests.cpp
)
target_link_libraries(
    zisla_windows_ai_agent_chat_request_planner_tests
    PRIVATE
        zisla_windows_core
)
target_compile_features(
    zisla_windows_ai_agent_chat_request_planner_tests
    PRIVATE
        cxx_std_20
)

if(MSVC)
    target_compile_options(
        zisla_windows_ai_agent_chat_request_planner_tests
        PRIVATE
            /W4 /WX /permissive- /utf-8
    )
else()
    target_compile_options(
        zisla_windows_ai_agent_chat_request_planner_tests
        PRIVATE
            -Wall -Wextra -Wpedantic -Werror
    )
endif()

add_test(
    NAME zisla_windows_ai_agent_chat_request_planner_tests
    COMMAND zisla_windows_ai_agent_chat_request_planner_tests
)

add_executable(
    zisla_windows_ai_agent_workspace_repository_tests
    AIAgentWorkspaceRepositoryTests.cpp
)
target_link_libraries(
    zisla_windows_ai_agent_workspace_repository_tests
    PRIVATE
        zisla_windows_core
        zisla_sqlite
)
target_compile_features(
    zisla_windows_ai_agent_workspace_repository_tests
    PRIVATE
        cxx_std_20
)

if(MSVC)
    target_compile_options(
        zisla_windows_ai_agent_workspace_repository_tests
        PRIVATE
            /W4 /WX /permissive- /utf-8
    )
else()
    target_compile_options(
        zisla_windows_ai_agent_workspace_repository_tests
        PRIVATE
            -Wall -Wextra -Wpedantic -Werror
    )
endif()

add_test(
    NAME zisla_windows_ai_agent_workspace_repository_tests
    COMMAND zisla_windows_ai_agent_workspace_repository_tests
)

add_executable(zisla_windows_cli_parser_tests CLIParserTests.cpp)
target_link_libraries(zisla_windows_cli_parser_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_cli_parser_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_cli_parser_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_cli_parser_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_cli_parser_tests
    COMMAND zisla_windows_cli_parser_tests
)

add_executable(zisla_windows_cli_application_tests CLIApplicationTests.cpp)
target_link_libraries(zisla_windows_cli_application_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_cli_application_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_cli_application_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_cli_application_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_cli_application_tests
    COMMAND zisla_windows_cli_application_tests
)

add_executable(zisla_windows_now_playing_tests NowPlayingTests.cpp)
target_link_libraries(zisla_windows_now_playing_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_now_playing_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_now_playing_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_now_playing_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_now_playing_tests
    COMMAND zisla_windows_now_playing_tests
)

add_executable(zisla_windows_side_notice_queue_tests SideNoticeQueueTests.cpp)
target_link_libraries(zisla_windows_side_notice_queue_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_side_notice_queue_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_side_notice_queue_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_side_notice_queue_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_side_notice_queue_tests
    COMMAND zisla_windows_side_notice_queue_tests
)

add_executable(zisla_windows_file_shelf_repository_tests FileShelfRepositoryTests.cpp)
target_link_libraries(
    zisla_windows_file_shelf_repository_tests
    PRIVATE
        zisla_windows_core
        zisla_sqlite
)
target_compile_features(zisla_windows_file_shelf_repository_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_file_shelf_repository_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_file_shelf_repository_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_file_shelf_repository_tests
    COMMAND zisla_windows_file_shelf_repository_tests
)

add_executable(zisla_windows_quick_notes_tests QuickNotesTests.cpp)
target_link_libraries(
    zisla_windows_quick_notes_tests
    PRIVATE
        zisla_windows_core
        zisla_sqlite
)
target_compile_features(zisla_windows_quick_notes_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_quick_notes_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_quick_notes_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_quick_notes_tests
    COMMAND zisla_windows_quick_notes_tests
)

add_executable(zisla_windows_clipboard_history_tests ClipboardHistoryTests.cpp)
target_link_libraries(
    zisla_windows_clipboard_history_tests
    PRIVATE
        zisla_windows_core
        zisla_sqlite
)
target_compile_features(zisla_windows_clipboard_history_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_clipboard_history_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_clipboard_history_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_clipboard_history_tests
    COMMAND zisla_windows_clipboard_history_tests
)

add_executable(zisla_windows_pomodoro_tests PomodoroTests.cpp)
target_link_libraries(zisla_windows_pomodoro_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_pomodoro_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_pomodoro_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_pomodoro_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_pomodoro_tests
    COMMAND zisla_windows_pomodoro_tests
)

add_executable(zisla_windows_power_request_tests PowerRequestTests.cpp)
target_link_libraries(zisla_windows_power_request_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_power_request_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_power_request_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_power_request_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_power_request_tests
    COMMAND zisla_windows_power_request_tests
)

add_executable(zisla_windows_cleaning_session_tests CleaningSessionTests.cpp)
target_link_libraries(zisla_windows_cleaning_session_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_cleaning_session_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_cleaning_session_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_cleaning_session_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_cleaning_session_tests
    COMMAND zisla_windows_cleaning_session_tests
)

add_executable(zisla_windows_teleprompter_tests TeleprompterTests.cpp)
target_link_libraries(zisla_windows_teleprompter_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_teleprompter_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_teleprompter_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_teleprompter_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_teleprompter_tests
    COMMAND zisla_windows_teleprompter_tests
)

add_executable(zisla_windows_camera_mirror_tests CameraMirrorTests.cpp)
target_link_libraries(zisla_windows_camera_mirror_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_camera_mirror_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_camera_mirror_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_camera_mirror_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_camera_mirror_tests
    COMMAND zisla_windows_camera_mirror_tests
)

add_executable(zisla_windows_weather_tests WeatherTests.cpp)
target_link_libraries(zisla_windows_weather_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_weather_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_weather_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_weather_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_weather_tests
    COMMAND zisla_windows_weather_tests
)

add_executable(zisla_windows_update_tests UpdateTests.cpp)
target_link_libraries(zisla_windows_update_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_update_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_update_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_update_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_update_tests
    COMMAND zisla_windows_update_tests
)

add_executable(zisla_windows_mail_tests MailTests.cpp)
target_link_libraries(zisla_windows_mail_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_mail_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_mail_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_mail_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_mail_tests
    COMMAND zisla_windows_mail_tests
)

add_executable(zisla_windows_system_monitor_tests SystemMonitorTests.cpp)
target_link_libraries(zisla_windows_system_monitor_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_system_monitor_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_system_monitor_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_system_monitor_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_system_monitor_tests
    COMMAND zisla_windows_system_monitor_tests
)

add_executable(zisla_windows_desktop_tools_tests DesktopToolsTests.cpp)
target_link_libraries(zisla_windows_desktop_tools_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_desktop_tools_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_desktop_tools_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_desktop_tools_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_desktop_tools_tests
    COMMAND zisla_windows_desktop_tools_tests
)

add_executable(zisla_windows_disk_cleanup_tests DiskCleanupTests.cpp)
target_link_libraries(zisla_windows_disk_cleanup_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_disk_cleanup_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_disk_cleanup_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_disk_cleanup_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_disk_cleanup_tests
    COMMAND zisla_windows_disk_cleanup_tests
)

add_executable(zisla_windows_download_tests DownloadTests.cpp)
target_link_libraries(zisla_windows_download_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_download_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_download_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_download_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_download_tests
    COMMAND zisla_windows_download_tests
)

add_executable(zisla_windows_browser_download_tests BrowserDownloadTests.cpp)
target_link_libraries(
    zisla_windows_browser_download_tests
    PRIVATE
        zisla_windows_core
        zisla_sqlite
)
target_compile_features(zisla_windows_browser_download_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_browser_download_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_browser_download_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_browser_download_tests
    COMMAND zisla_windows_browser_download_tests
)

add_executable(zisla_windows_calendar_tests CalendarTests.cpp)
target_link_libraries(
    zisla_windows_calendar_tests
    PRIVATE
        zisla_windows_core
        zisla_sqlite
)
target_compile_features(zisla_windows_calendar_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_calendar_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_calendar_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_calendar_tests
    COMMAND zisla_windows_calendar_tests
)

add_executable(zisla_windows_pet_tests PetTests.cpp)
target_link_libraries(zisla_windows_pet_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_pet_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_pet_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_pet_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_pet_tests
    COMMAND zisla_windows_pet_tests
)

add_executable(zisla_windows_voice_input_tests VoiceInputTests.cpp)
target_link_libraries(zisla_windows_voice_input_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_voice_input_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_voice_input_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_voice_input_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_voice_input_tests
    COMMAND zisla_windows_voice_input_tests
)

add_executable(zisla_windows_voice_hotkey_tests VoiceHotkeyTests.cpp)
target_link_libraries(zisla_windows_voice_hotkey_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_voice_hotkey_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_voice_hotkey_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_voice_hotkey_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_voice_hotkey_tests
    COMMAND zisla_windows_voice_hotkey_tests
)

add_executable(zisla_windows_pdf_processing_tests PDFProcessingTests.cpp)
target_link_libraries(zisla_windows_pdf_processing_tests PRIVATE zisla_windows_core)
target_compile_features(zisla_windows_pdf_processing_tests PRIVATE cxx_std_20)

if(MSVC)
    target_compile_options(zisla_windows_pdf_processing_tests PRIVATE /W4 /WX /permissive- /utf-8)
else()
    target_compile_options(zisla_windows_pdf_processing_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_test(
    NAME zisla_windows_pdf_processing_tests
    COMMAND zisla_windows_pdf_processing_tests
)

if(TARGET zisla_windows_qpdf_adapter)
    add_executable(zisla_windows_qpdf_adapter_tests QPDFAdapterTests.cpp)
    target_link_libraries(
        zisla_windows_qpdf_adapter_tests
        PRIVATE
            zisla_windows_qpdf_adapter
    )
    target_compile_features(zisla_windows_qpdf_adapter_tests PRIVATE cxx_std_20)
    if(MSVC)
        target_compile_options(zisla_windows_qpdf_adapter_tests PRIVATE /W4 /WX /permissive- /utf-8)
    else()
        target_compile_options(zisla_windows_qpdf_adapter_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
    endif()
    add_test(
        NAME zisla_windows_qpdf_adapter_tests
        COMMAND zisla_windows_qpdf_adapter_tests
    )
endif()

if(TARGET zisla_windows_pdfium_adapter)
    function(zisla_copy_pdfium_runtime target)
        add_custom_command(
            TARGET ${target}
            POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "$<TARGET_FILE:pdfium>"
                "$<TARGET_FILE_DIR:${target}>"
            VERBATIM
        )
    endfunction()

    add_executable(zisla_windows_pdfium_adapter_tests PDFiumAdapterTests.cpp)
    target_link_libraries(
        zisla_windows_pdfium_adapter_tests
        PRIVATE
            zisla_windows_pdfium_adapter
    )
    zisla_copy_pdfium_runtime(zisla_windows_pdfium_adapter_tests)
    target_compile_features(zisla_windows_pdfium_adapter_tests PRIVATE cxx_std_20)
    if(MSVC)
        target_compile_options(zisla_windows_pdfium_adapter_tests PRIVATE /W4 /WX /permissive- /utf-8)
    else()
        target_compile_options(zisla_windows_pdfium_adapter_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
    endif()
    add_test(
        NAME zisla_windows_pdfium_adapter_tests
        COMMAND zisla_windows_pdfium_adapter_tests
    )
endif()

if(TARGET zisla_windows_pdf_processing_service)
    add_executable(zisla_windows_pdf_processing_service_tests PDFProcessingServiceTests.cpp)
    target_link_libraries(
        zisla_windows_pdf_processing_service_tests
        PRIVATE
            zisla_windows_pdf_processing_service
    )
    if(TARGET zisla_windows_pdfium_adapter)
        zisla_copy_pdfium_runtime(zisla_windows_pdf_processing_service_tests)
    endif()
    target_compile_features(zisla_windows_pdf_processing_service_tests PRIVATE cxx_std_20)
    if(TARGET zisla_windows_pdfium_adapter)
        target_compile_definitions(
            zisla_windows_pdf_processing_service_tests
            PRIVATE
                ZISLA_HAS_PDFIUM_ADAPTER=1
        )
    endif()
    if(MSVC)
        target_compile_options(zisla_windows_pdf_processing_service_tests PRIVATE /W4 /WX /permissive- /utf-8)
    else()
        target_compile_options(zisla_windows_pdf_processing_service_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
    endif()
    add_test(
        NAME zisla_windows_pdf_processing_service_tests
        COMMAND zisla_windows_pdf_processing_service_tests
    )

    add_executable(zisla_windows_local_office_adapter_tests LocalOfficeAdapterTests.cpp)
    target_link_libraries(
        zisla_windows_local_office_adapter_tests
        PRIVATE
            zisla_windows_pdf_processing_service
    )
    if(TARGET zisla_windows_pdfium_adapter)
        zisla_copy_pdfium_runtime(zisla_windows_local_office_adapter_tests)
    endif()
    target_compile_features(zisla_windows_local_office_adapter_tests PRIVATE cxx_std_20)
    if(MSVC)
        target_compile_options(zisla_windows_local_office_adapter_tests PRIVATE /W4 /WX /permissive- /utf-8)
    else()
        target_compile_options(zisla_windows_local_office_adapter_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
    endif()
    add_test(
        NAME zisla_windows_local_office_adapter_tests
        COMMAND zisla_windows_local_office_adapter_tests
    )
endif()
