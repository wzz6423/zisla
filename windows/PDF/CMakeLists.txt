if(ZISLA_ENABLE_QPDF_ADAPTER)
    add_library(zisla_windows_qpdf_adapter STATIC
        QPDFAdapter.cpp
    )

    target_compile_features(zisla_windows_qpdf_adapter PUBLIC cxx_std_20)
    target_include_directories(zisla_windows_qpdf_adapter
        PUBLIC
            ${CMAKE_CURRENT_SOURCE_DIR}
    )
    target_link_libraries(zisla_windows_qpdf_adapter
        PUBLIC
            zisla_windows_core
            qpdf::libqpdf
    )
    target_link_directories(zisla_windows_qpdf_adapter
        INTERFACE
            ${ZISLA_QPDF_LIBRARY_DIR}
    )

    if(MSVC)
        target_compile_options(zisla_windows_qpdf_adapter PRIVATE /W4 /WX /permissive- /utf-8)
    else()
        target_compile_options(zisla_windows_qpdf_adapter PRIVATE -Wall -Wextra -Wpedantic -Werror)
    endif()
endif()

if(ZISLA_ENABLE_PDFIUM_ADAPTER)
    add_library(zisla_windows_pdfium_adapter STATIC
        PDFiumAdapter.cpp
    )
    target_compile_features(zisla_windows_pdfium_adapter PUBLIC cxx_std_20)
    target_include_directories(zisla_windows_pdfium_adapter
        PUBLIC
            ${CMAKE_CURRENT_SOURCE_DIR}
    )
    target_link_libraries(zisla_windows_pdfium_adapter
        PUBLIC
            zisla_windows_core
            pdfium
            zisla_jpeg_static
            zlibstatic
    )
    if(MSVC)
        target_compile_options(zisla_windows_pdfium_adapter PRIVATE /W4 /WX /permissive- /utf-8)
    else()
        target_compile_options(zisla_windows_pdfium_adapter PRIVATE -Wall -Wextra -Wpedantic -Werror)
    endif()
endif()

if(TARGET zisla_windows_qpdf_adapter)
    add_library(zisla_windows_pdf_processing_service STATIC
        LocalOfficeAdapter.cpp
        PDFProcessingService.cpp
    )

    target_compile_features(zisla_windows_pdf_processing_service PUBLIC cxx_std_20)
    target_include_directories(zisla_windows_pdf_processing_service
        PUBLIC
            ${CMAKE_CURRENT_SOURCE_DIR}
    )
    target_link_libraries(zisla_windows_pdf_processing_service
        PUBLIC
            zisla_windows_qpdf_adapter
    )

    if(TARGET zisla_windows_pdfium_adapter)
        target_link_libraries(zisla_windows_pdf_processing_service
            PUBLIC
                zisla_windows_pdfium_adapter
        )
        target_compile_definitions(zisla_windows_pdf_processing_service
            PRIVATE
                ZISLA_HAS_PDFIUM_ADAPTER=1
        )
    endif()

    if(MSVC)
        target_compile_options(zisla_windows_pdf_processing_service PRIVATE /W4 /WX /permissive- /utf-8)
    else()
        target_compile_options(zisla_windows_pdf_processing_service PRIVATE -Wall -Wextra -Wpedantic -Werror)
    endif()
endif()
