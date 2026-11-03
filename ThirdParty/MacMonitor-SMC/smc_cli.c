#include "SMC.h"

#include <ctype.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static void printUsage(FILE *stream) {
    fprintf(stream, "Usage: smc -k {CHTE|BCLM} {-r|-w hex-bytes} | --temperatures\n");
}

static int printTemperatureForKey(io_connect_t connection, const char *key) {
    const unsigned int sp78 = 0x73703738;
    SMCKeyData_t value;
    if (SMCReadKey(connection, key, &value) != kIOReturnSuccess ||
        value.keyInfo.dataType != sp78 || value.keyInfo.dataSize != 2) {
        return 0;
    }

    const unsigned char high = (unsigned char)value.bytes[0];
    const unsigned char low = (unsigned char)value.bytes[1];
    const double temperature = (double)(int16_t)((high << 8) | low) / 256.0;
    if (temperature <= 15.0 || temperature >= 125.0) {
        return 0;
    }
    printf("%s=%.2f\n", key, temperature);
    return 1;
}

static int printTemperatures(io_connect_t connection) {
    SMCKeyData_t keyCountData;
    int count = 0;
    if (SMCReadKey(connection, "#KEY", &keyCountData) == kIOReturnSuccess &&
        keyCountData.keyInfo.dataSize == 4) {
        const unsigned int keyCount =
            ((unsigned int)(unsigned char)keyCountData.bytes[0] << 24) |
            ((unsigned int)(unsigned char)keyCountData.bytes[1] << 16) |
            ((unsigned int)(unsigned char)keyCountData.bytes[2] << 8) |
            (unsigned int)(unsigned char)keyCountData.bytes[3];
        if (keyCount <= 8192) {
            for (unsigned int index = 0; index < keyCount; index++) {
                unsigned int keyCode = 0;
                if (SMCReadKeyFromIndex(connection, index, &keyCode) != kIOReturnSuccess) {
                    continue;
                }
                char key[5] = {
                    (char)(keyCode >> 24),
                    (char)(keyCode >> 16),
                    (char)(keyCode >> 8),
                    (char)keyCode,
                    '\0'
                };
                if (key[0] != 'T' && key[0] != 't') {
                    continue;
                }
                count += printTemperatureForKey(connection, key);
            }
        }
    }

    if (count > 0) {
        return count;
    }

    static const char *keys[] = {
        "TC0D", "TC0P", "TC0C", "TC0E", "TC0F", "TC0H", "TC0J",
        "TC1C", "TC2C", "TC3C", "TC4C", "TC5C", "TC6C", "TC7C",
        "TG0D", "TG0H", "TG0P", "TG1D", "TG1H", "TG1P",
        "TG2D", "TG2H", "TG2P", "Tg0D", "Tg0H", "Tg0P",
        "TB0T", "TB1T", "TB2T",
        "TH0F", "TH0P", "TH0T", "TH1F", "TH1P", "TH1T",
        "TH2F", "TH2P", "TH2T", "TH3F", "TH3P", "TH3T",
        "TH4F", "TH4P", "TH4T",
        "TM0P", "TM0S", "TM1P", "TM1S", "TM2P", "TM2S",
        "Tm0P", "Tm0S", "Tm1P", "Tm1S",
        "Tp0P", "Tp0S", "Tp1P", "Tp1S", "Ts0P", "Ts0S", "Ts1P", "Ts1S",
        "TA0P", "TA1P", "TA2P"
    };
    for (size_t index = 0; index < sizeof(keys) / sizeof(keys[0]); index++) {
        count += printTemperatureForKey(connection, keys[index]);
    }
    return count;
}

static int isSupportedKey(const char *key) {
    return strcmp(key, "CHTE") == 0 || strcmp(key, "BCLM") == 0;
}

static int hexValue(char character) {
    if (character >= '0' && character <= '9') {
        return character - '0';
    }
    character = (char)tolower((unsigned char)character);
    if (character >= 'a' && character <= 'f') {
        return character - 'a' + 10;
    }
    return -1;
}

static int parseHexBytes(const char *value, SMCBytes_t bytes, unsigned int size) {
    if (size == 0 || size > sizeof(SMCBytes_t) || strlen(value) != size * 2) {
        return 0;
    }

    for (unsigned int index = 0; index < size; index++) {
        int high = hexValue(value[index * 2]);
        int low = hexValue(value[index * 2 + 1]);
        if (high < 0 || low < 0) {
            return 0;
        }
        bytes[index] = (char)((high << 4) | low);
    }
    return 1;
}

static void printKeyValue(const char *key, const SMCKeyData_t *value) {
    char dataType[5] = {
        (char)(value->keyInfo.dataType >> 24),
        (char)(value->keyInfo.dataType >> 16),
        (char)(value->keyInfo.dataType >> 8),
        (char)value->keyInfo.dataType,
        '\0'
    };

    printf("%-4s  [%-4s]  (bytes", key, dataType);
    for (unsigned int index = 0; index < value->keyInfo.dataSize; index++) {
        printf(" %02x", (unsigned char)value->bytes[index]);
    }
    puts(")");
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--temperatures") == 0) {
        io_connect_t connection = SMCOpen();
        if (connection == IO_OBJECT_NULL) {
            fprintf(stderr, "Error: no SMC found or access denied\n");
            return 1;
        }
        const int result = printTemperatures(connection);
        SMCClose(connection);
        return result > 0 ? 0 : 1;
    }
    const char *key = NULL;
    const char *writeValue = NULL;
    int shouldRead = 0;

    for (int index = 1; index < argc; index++) {
        if (strcmp(argv[index], "-h") == 0) {
            printUsage(stdout);
            return 0;
        }
        if (strcmp(argv[index], "-k") == 0 && index + 1 < argc) {
            key = argv[++index];
        } else if (strcmp(argv[index], "-r") == 0) {
            shouldRead = 1;
        } else if (strcmp(argv[index], "-w") == 0 && index + 1 < argc) {
            writeValue = argv[++index];
        } else {
            printUsage(stderr);
            return 2;
        }
    }

    if (key == NULL || strlen(key) != 4 || !isSupportedKey(key) ||
        (shouldRead == (writeValue != NULL))) {
        printUsage(stderr);
        return 2;
    }

    io_connect_t connection = SMCOpen();
    if (connection == IO_OBJECT_NULL) {
        fprintf(stderr, "Error: no SMC found or access denied\n");
        return 1;
    }

    int exitCode = 0;
    if (shouldRead) {
        SMCKeyData_t value;
        kern_return_t result = SMCReadKey(connection, key, &value);
        if (result != kIOReturnSuccess) {
            fprintf(stderr, "Error: SMCReadKey() = %08x\n", result);
            exitCode = 1;
        } else if (value.keyInfo.dataSize > sizeof(value.bytes)) {
            fprintf(stderr, "Error: invalid SMC data size\n");
            exitCode = 1;
        } else {
            printKeyValue(key, &value);
        }
    } else {
        SMCKeyData_keyInfo_t keyInfo = {0};
        kern_return_t result = SMCGetKeyInfo(connection, key, &keyInfo);
        SMCBytes_t bytes = {0};
        if (result != kIOReturnSuccess) {
            fprintf(stderr, "Error: SMCGetKeyInfo() = %08x\n", result);
            exitCode = 1;
        } else if (!parseHexBytes(writeValue, bytes, keyInfo.dataSize)) {
            fprintf(stderr, "Error: invalid key or byte value\n");
            exitCode = 1;
        } else if (strcmp(key, "CHTE") == 0) {
            const int isBypassOn = keyInfo.dataSize == 4 &&
                                   bytes[0] == 1 && bytes[1] == 0 &&
                                   bytes[2] == 0 && bytes[3] == 0;
            const int isBypassOff = keyInfo.dataSize == 4 &&
                                    bytes[0] == 0 && bytes[1] == 0 &&
                                    bytes[2] == 0 && bytes[3] == 0;
            if (!isBypassOn && !isBypassOff) {
                fprintf(stderr, "Error: unsupported CHTE value\n");
                exitCode = 2;
            }
        } else if (strcmp(key, "BCLM") == 0) {
            const unsigned char limit = (unsigned char)bytes[0];
            if (keyInfo.dataSize != 1 || limit < 50 || limit > 100) {
                fprintf(stderr, "Error: Intel charge limit must be between 50 and 100\n");
                exitCode = 2;
            }
        }

        if (exitCode == 0) {
            result = SMCWriteKey(connection, key, keyInfo.dataType, bytes, keyInfo.dataSize);
            if (result != kIOReturnSuccess) {
                fprintf(stderr, "Error: SMCWriteKey() = %08x\n", result);
                exitCode = 1;
            }
        }
    }

    SMCClose(connection);
    return exitCode;
}
