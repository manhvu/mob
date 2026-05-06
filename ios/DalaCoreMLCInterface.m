// DalaCoreMLCInterface.m - C interface for Rust to call Objective-C CoreML code

#import "DalaCoreMLManager.h"

// C interface functions for Rust to call
#ifdef __cplusplus
extern "C" {
#endif

typedef void (*DalaCoreMLPredictionCallback)(const char *modelIdentifier,
                                             const char *resultJSON,
                                             const char *error);

void DalaCoreMLLoadModel(const char *modelPath, const char *identifier, char *errorBuffer, size_t errorBufferSize) {
    NSString *path = [NSString stringWithUTF8String:modelPath];
    NSString *ident = [NSString stringWithUTF8String:identifier];
    NSError *error = nil;

    BOOL success = [[DalaCoreMLManager sharedManager] loadModelAtPath:path
                                                        identifier:ident
                                                             error:&error];

    if (!success && errorBuffer && errorBufferSize > 0) {
        NSString *errorMsg = [error localizedDescription] ?: @"Unknown error";
        strncpy(errorBuffer, [errorMsg UTF8String], errorBufferSize - 1);
        errorBuffer[errorBufferSize - 1] = '\0';
    }
}

void DalaCoreMLUnloadModel(const char *identifier) {
    NSString *ident = [NSString stringWithUTF8String:identifier];
    [[DalaCoreMLManager sharedManager] unloadModelWithIdentifier:ident];
}

bool DalaCoreMLIsModelLoaded(const char *identifier) {
    NSString *ident = [NSString stringWithUTF8String:identifier];
    return [[DalaCoreMLManager sharedManager] isModelLoaded:ident];
}

void DalaCoreMLPredict(const char *identifier,
                       const char *inputsJSON,
                       DalaCoreMLPredictionCallback callback) {
    NSString *ident = [NSString stringWithUTF8String:identifier];
    NSString *jsonStr = [NSString stringWithUTF8String:inputsJSON];

    // Parse JSON inputs
    NSError *jsonError = nil;
    NSData *jsonData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *inputs = [NSJSONSerialization JSONObjectWithData:jsonData
                                                         options:0
                                                           error:&jsonError];

    if (!inputs || jsonError) {
        if (callback) {
            NSString *errorMsg = [jsonError localizedDescription] ?: @"Invalid JSON input";
            callback(ident.UTF8String, NULL, [errorMsg UTF8String]);
        }
        return;
    }

    [[DalaCoreMLManager sharedManager] predictWithModel:ident
                                                inputs:inputs
                                               callback:callback];
}

// Get list of loaded models as JSON array
const char *DalaCoreMLLoadedModels() {
    NSArray *models = [[DalaCoreMLManager sharedManager] loadedModelIdentifiers];
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:models
                                                         options:0
                                                           error:&jsonError];
    if (jsonError) {
        return NULL;
    }

    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    // Copy string to heap so Rust can manage it
    return strdup([jsonString UTF8String]);
}

void DalaCoreMLFreeString(const char *str) {
    if (str) {
        free((void *)str);
    }
}

#ifdef __cplusplus
}
#endif
