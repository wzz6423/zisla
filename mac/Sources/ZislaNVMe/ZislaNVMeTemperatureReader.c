#include "ZislaNVMeTemperatureReader.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitKeys.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
#include <math.h>

static CFMutableDictionaryRef smartMatchingDictionary(void) {
    CFMutableDictionaryRef matching = IOServiceMatching("IOBlockStorageDevice");
    if (matching == NULL) {
        return NULL;
    }

    CFMutableDictionaryRef properties = CFDictionaryCreateMutable(
        kCFAllocatorDefault,
        0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    if (properties == NULL) {
        CFRelease(matching);
        return NULL;
    }

    CFDictionarySetValue(properties, CFSTR(kIOPropertyNVMeSMARTCapableKey), kCFBooleanTrue);
    CFDictionarySetValue(matching, CFSTR(kIOPropertyMatchKey), properties);
    CFRelease(properties);
    return matching;
}

double ZislaReadNVMeTemperatureCelsius(void) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    CFMutableDictionaryRef matching = smartMatchingDictionary();
    if (matching == NULL || IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) != KERN_SUCCESS) {
        return NAN;
    }

    double temperature = NAN;
    for (io_service_t service = IOIteratorNext(iterator); service != IO_OBJECT_NULL; service = IOIteratorNext(iterator)) {
        IOCFPlugInInterface **plugin = NULL;
        SInt32 score = 0;
        IOReturn result = IOCreatePlugInInterfaceForService(
            service,
            kIONVMeSMARTUserClientTypeID,
            kIOCFPlugInInterfaceID,
            &plugin,
            &score
        );

        if (result == KERN_SUCCESS && plugin != NULL) {
            IONVMeSMARTInterface **smart = NULL;
            HRESULT queryResult = (*plugin)->QueryInterface(
                plugin,
                CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID),
                (LPVOID *)&smart
            );

            if (queryResult == S_OK && smart != NULL) {
                NVMeSMARTData data = {0};
                result = (*smart)->SMARTReadData(smart, &data);
                (*smart)->Release(smart);
                if (result == KERN_SUCCESS) {
                    const double celsius = (double)CFSwapInt16LittleToHost(data.TEMPERATURE) - 273.15;
                    if (isfinite(celsius) && celsius >= 0 && celsius <= 120) {
                        temperature = celsius;
                    }
                }
            }
            IODestroyPlugInInterface(plugin);
        }

        IOObjectRelease(service);
        if (isfinite(temperature)) {
            break;
        }
    }

    IOObjectRelease(iterator);
    return temperature;
}
