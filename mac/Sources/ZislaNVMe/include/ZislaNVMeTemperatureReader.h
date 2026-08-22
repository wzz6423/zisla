#ifndef ZISLA_NVME_TEMPERATURE_READER_H
#define ZISLA_NVME_TEMPERATURE_READER_H

/// Returns the NVMe SMART temperature in Celsius, or NAN when unavailable.
double ZislaReadNVMeTemperatureCelsius(void);

#endif
