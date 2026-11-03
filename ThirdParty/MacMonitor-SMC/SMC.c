/*
 * SMC protocol implementation adapted from MacMonitor:
 * https://github.com/ryyansafar/MacMonitor/tree/f005cee0b3a6aae5f21da85acaf7366ca60abb5d/Macmonitor
 * Copyright (c) 2025-2026 MacMonitor Contributors. Licensed under MIT.
 */

#include "SMC.h"

#include <string.h>

static unsigned int SMCFourCC(const char *key) {
    return ((unsigned int)(unsigned char)key[0] << 24) |
           ((unsigned int)(unsigned char)key[1] << 16) |
           ((unsigned int)(unsigned char)key[2] << 8) |
           (unsigned int)(unsigned char)key[3];
}

io_connect_t SMCOpen(void) {
    CFMutableDictionaryRef matchingDictionary = IOServiceMatching("AppleSMC");
    if (matchingDictionary == NULL) {
        return 0;
    }

    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t result = IOServiceGetMatchingServices(
        kIOMainPortDefault,
        matchingDictionary,
        &iterator
    );
    if (result != kIOReturnSuccess) {
        return 0;
    }

    io_object_t device = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (device == IO_OBJECT_NULL) {
        return 0;
    }

    io_connect_t connection = IO_OBJECT_NULL;
    result = IOServiceOpen(device, mach_task_self(), 0, &connection);
    IOObjectRelease(device);
    return result == kIOReturnSuccess ? connection : IO_OBJECT_NULL;
}

kern_return_t SMCClose(io_connect_t connection) {
    return IOServiceClose(connection);
}

static kern_return_t SMCCall(
    io_connect_t connection,
    unsigned char command,
    SMCKeyData_t *input,
    SMCKeyData_t *output
) {
    input->data8 = command;
    size_t outputSize = sizeof(*output);
    return IOConnectCallStructMethod(
        connection,
        KERNEL_INDEX_SMC,
        input,
        sizeof(*input),
        output,
        &outputSize
    );
}

kern_return_t SMCGetKeyInfo(
    io_connect_t connection,
    const char *key,
    SMCKeyData_keyInfo_t *keyInfo
) {
    SMCKeyData_t input = {0};
    SMCKeyData_t output = {0};
    input.key = SMCFourCC(key);

    kern_return_t result = SMCCall(connection, SMC_CMD_READ_KEYINFO, &input, &output);
    if (result == kIOReturnSuccess) {
        *keyInfo = output.keyInfo;
    }
    return result;
}

kern_return_t SMCReadKeyFromIndex(
    io_connect_t connection,
    unsigned int index,
    unsigned int *key
) {
    SMCKeyData_t input = {0};
    SMCKeyData_t output = {0};
    input.data32 = index;
    kern_return_t result = SMCCall(connection, SMC_CMD_READ_INDEX, &input, &output);
    if (result == kIOReturnSuccess) {
        *key = output.key;
    }
    return result;
}

kern_return_t SMCReadKey(
    io_connect_t connection,
    const char *key,
    SMCKeyData_t *value
) {
    SMCKeyData_t input = {0};
    SMCKeyData_t output = {0};
    memset(value, 0, sizeof(*value));
    input.key = SMCFourCC(key);

    kern_return_t result = SMCCall(connection, SMC_CMD_READ_KEYINFO, &input, &output);
    if (result != kIOReturnSuccess) {
        return result;
    }

    value->keyInfo = output.keyInfo;
    input.keyInfo.dataSize = output.keyInfo.dataSize;
    memset(&output, 0, sizeof(output));
    result = SMCCall(connection, SMC_CMD_READ_BYTES, &input, &output);
    if (result == kIOReturnSuccess) {
        memcpy(value->bytes, output.bytes, sizeof(value->bytes));
    }
    return result;
}

kern_return_t SMCWriteKey(
    io_connect_t connection,
    const char *key,
    unsigned int dataType,
    const SMCBytes_t bytes,
    unsigned int dataSize
) {
    if (dataSize > sizeof(SMCBytes_t)) {
        return kIOReturnBadArgument;
    }

    SMCKeyData_t input = {0};
    SMCKeyData_t output = {0};
    input.key = SMCFourCC(key);
    input.keyInfo.dataType = dataType;
    input.keyInfo.dataSize = dataSize;
    memcpy(input.bytes, bytes, dataSize);
    return SMCCall(connection, SMC_CMD_WRITE_BYTES, &input, &output);
}
