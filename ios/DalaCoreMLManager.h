// DalaCoreMLManager.h - iOS CoreML wrapper for Dala
// Provides CoreML functionality via Objective-C to be called from Rust

#import <Foundation/Foundation.h>
#import <CoreML/CoreML.h>

NS_ASSUME_NONNULL_BEGIN

@interface DalaCoreMLModel : NSObject

@property (nonatomic, strong) MLModel *model;
@property (nonatomic, strong) NSString *modelIdentifier;

@end

// Callback types for async predictions
typedef void (*DalaCoreMLPredictionCallback)(const char *modelIdentifier,
                                              const char *resultJSON,
                                              const char *error);

@interface DalaCoreMLManager : NSObject

+ (instancetype)sharedManager;

// Model management
- (BOOL)loadModelAtPath:(NSString *)modelPath identifier:(NSString *)identifier error:(NSError **)error;
- (void)unloadModelWithIdentifier:(NSString *)identifier;
- (BOOL)isModelLoaded:(NSString *)identifier;

// Prediction
- (void)predictWithModel:(NSString *)identifier
                   inputs:(NSDictionary<NSString *, id> *)inputs
                  callback:(DalaCoreMLPredictionCallback)callback;

// List loaded models
- (NSArray<NSString *> *)loadedModelIdentifiers;

@end

NS_ASSUME_NONNULL_END
