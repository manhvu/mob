// DalaCoreMLManager.m - CoreML manager implementation

#import "DalaCoreMLManager.h"
#import <CoreML/CoreML.h>

@interface DalaCoreMLModel ()
@property (nonatomic, strong) MLModel *model;
@property (nonatomic, strong) NSString *modelIdentifier;
@end

@implementation DalaCoreMLModel
@end

@interface DalaCoreMLManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, DalaCoreMLModel *> *models;
@end

@implementation DalaCoreMLManager

+ (instancetype)sharedManager {
    static DalaCoreMLManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[self alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _models = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)loadModelAtPath:(NSString *)modelPath identifier:(NSString *)identifier error:(NSError **)error {
    NSURL *modelURL = [NSURL fileURLWithPath:modelPath];

    if (![[NSFileManager defaultManager] fileExistsAtPath:modelPath]) {
        if (error) {
            *error = [NSError errorWithDomain:@"DalaCoreML"
                                             code:404
                                         userInfo:@{NSLocalizedDescriptionKey: @"Model file not found"}];
        }
        return NO;
    }

    NSError *loadError = nil;
    MLModel *model = [MLModel modelWithContentsOfURL:modelURL error:&loadError];

    if (!model) {
        if (error) {
            *error = loadError;
        }
        return NO;
    }

    DalaCoreMLModel *coreMLModel = [[DalaCoreMLModel alloc] init];
    coreMLModel.model = model;
    coreMLModel.modelIdentifier = identifier;

    @synchronized (self.models) {
        self.models[identifier] = coreMLModel;
    }

    return YES;
}

- (void)unloadModelWithIdentifier:(NSString *)identifier {
    @synchronized (self.models) {
        [self.models removeObjectForKey:identifier];
    }
}

- (BOOL)isModelLoaded:(NSString *)identifier {
    @synchronized (self.models) {
        return self.models[identifier] != nil;
    }
}

- (void)predictWithModel:(NSString *)identifier
                   inputs:(NSDictionary<NSString *, id> *)inputs
                  callback:(DalaCoreMLPredictionCallback)callback {

    DalaCoreMLModel *coreMLModel = nil;
    @synchronized (self.models) {
        coreMLModel = self.models[identifier];
    }

    if (!coreMLModel) {
        if (callback) {
            callback([identifier UTF8String], NULL, "Model not loaded");
        }
        return;
    }

    NSError *error = nil;
    MLPredictionOptions *options = [[MLPredictionOptions alloc] init];

    // Convert inputs dictionary to MLDictionaryFeatureProvider
    NSMutableDictionary<NSString *, MLFeatureValue *> *featureDict = [NSMutableDictionary dictionary];

    for (NSString *key in inputs) {
        id value = inputs[key];

        if ([value isKindOfClass:[NSNumber class]]) {
            // Handle numeric input
            NSNumber *num = (NSNumber *)value;
            MLFeatureValue *featureValue = [MLFeatureValue featureValueWithDouble:[num doubleValue]];
            featureDict[key] = featureValue;

        } else if ([value isKindOfClass:[NSData class]]) {
            // Handle multi-array input (convert NSData to MLMultiArray)
            // This is a simplified version - real implementation would need shape info
            featureDict[key] = [MLFeatureValue featureValueWithData:(NSData *)value];

        } else if ([value isKindOfClass:[NSString class]]) {
            // Handle string input
            featureDict[key] = [MLFeatureValue featureValueWithString:(NSString *)value];

        } else if ([value isKindOfClass:[NSArray class]]) {
            // Handle array input - convert to MLMultiArray
            NSArray *array = (NSArray *)value;
            NSError *multiArrayError = nil;
            MLMultiArray *multiArray = [[MLMultiArray alloc] initWithShape:@[@(array.count)]
                                                         dataType:MLMultiArrayDataTypeDouble
                                                            error:&multiArrayError];
            if (multiArray && !multiArrayError) {
                for (NSUInteger i = 0; i < array.count; i++) {
                    multiArray[i] = array[i];
                }
                featureDict[key] = [MLFeatureValue featureValueWithMultiArray:multiArray];
            }
        }
    }

    NSError *dictError = nil;
    MLFeatureProvider *inputProvider = [[MLDictionaryFeatureProvider alloc] initWithDictionary:featureDict
                                                                                    error:&dictError];
    if (dictError) {
        if (callback) {
            callback([identifier UTF8String], NULL, [[dictError localizedDescription] UTF8String]);
        }
        return;
    }

    // Make prediction
    id<MLFeatureProvider> output = [coreMLModel.model predictionFromFeatures:inputProvider
                                                                  options:options
                                                                            error:&error];
    if (error) {
        if (callback) {
            callback([identifier UTF8String], NULL, [[error localizedDescription] UTF8String]);
        }
        return;
    }

    // Convert output to JSON
    NSMutableDictionary *resultDict = [NSMutableDictionary dictionary];
    for (NSString *featureName in output.featureNames) {
        MLFeatureValue *value = [output featureValueForName:featureName];

        if (value.type == MLFeatureTypeDouble) {
            resultDict[featureName] = @(value.doubleValue);
        } else if (value.type == MLFeatureTypeInt64) {
            resultDict[featureName] = @(value.int64Value);
        } else if (value.type == MLFeatureTypeString) {
            resultDict[featureName] = value.stringValue;
        } else if (value.type == MLFeatureTypeMultiArray) {
            // Convert MLMultiArray to NSArray
            MLMultiArray *multiArray = value.multiArrayValue;
            NSMutableArray *array = [NSMutableArray array];
            for (NSUInteger i = 0; i < multiArray.count; i++) {
                [array addObject:multiArray[i]];
            }
            resultDict[featureName] = array;
        }
    }

    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:resultDict
                                                         options:0
                                                           error:&jsonError];
    if (jsonError) {
        if (callback) {
            callback([identifier UTF8String], NULL, [[jsonError localizedDescription] UTF8String]);
        }
        return;
    }

    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

    if (callback) {
        callback([identifier UTF8String], [jsonString UTF8String], NULL);
    }
}

- (NSArray<NSString *> *)loadedModelIdentifiers {
    @synchronized (self.models) {
        return [self.models allKeys];
    }
}

@end
