/*
 * SMC protocol implementation adapted from MacMonitor:
 * https://github.com/ryyansafar/MacMonitor/tree/f005cee0b3a6aae5f21da85acaf7366ca60abb5d/Macmonitor
 * Copyright (c) 2025-2026 MacMonitor Contributors. Licensed under MIT.
 */

#ifndef MACMATE_SMC_H
#define MACMATE_SMC_H

#include <IOKit/IOKitLib.h>

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_WRITE_BYTES 6
#define SMC_CMD_READ_INDEX 8
#define SMC_CMD_READ_KEYINFO 9

typedef char SMCBytes_t[32];

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    unsigned short release;
} SMCKeyData_vers_t;

typedef struct {
    unsigned short version;
    unsigned short length;
    unsigned int cpuPLimit;
    unsigned int gpuPLimit;
    unsigned int memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    unsigned int dataSize;
    unsigned int dataType;
    char dataAttributes;
} SMCKeyData_keyInfo_t;

typedef struct {
    unsigned int key;
    SMCKeyData_vers_t vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t keyInfo;
    char result;
    char status;
    char data8;
    unsigned int data32;
    SMCBytes_t bytes;
} SMCKeyData_t;

io_connect_t SMCOpen(void);
kern_return_t SMCClose(io_connect_t connection);
kern_return_t SMCReadKey(io_connect_t connection, const char *key, SMCKeyData_t *value);
kern_return_t SMCReadKeyFromIndex(io_connect_t connection, unsigned int index, unsigned int *key);
kern_return_t SMCGetKeyInfo(io_connect_t connection, const char *key, SMCKeyData_keyInfo_t *keyInfo);
kern_return_t SMCWriteKey(
    io_connect_t connection,
    const char *key,
    unsigned int dataType,
    const SMCBytes_t bytes,
    unsigned int dataSize
);

#endif
