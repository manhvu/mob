// MobNode.m — Mob UI tree node implementation.

#import "MobNode.h"
#import <math.h>

@implementation MobNode

- (instancetype)init {
    if ((self = [super init])) {
        _textSize      = 14.0;
        _padding       = 0.0;
        _paddingTop    = -1.0;
        _paddingRight  = -1.0;
        _paddingBottom = -1.0;
        _paddingLeft   = -1.0;
        _fontWeight    = @"regular";
        _textAlign     = @"left";
        _italic        = NO;
        _lineHeight    = 0.0;
        _letterSpacing = 0.0;
        _thickness     = 1.0;
        _fixedSize     = 0.0;
        _value         = NAN;   // NaN = indeterminate (progress) or not-yet-set (slider)
        _minValue      = 0.0;
        _maxValue      = 1.0;
        _checked       = NO;
        _axis            = @"vertical";
        _showIndicator   = YES;
        _keyboardTypeStr = @"default";
        _returnKeyStr    = @"done";
        _contentModeStr  = @"fit";
        _fixedWidth      = 0.0;
        _fixedHeight     = 0.0;
        _fillWidth       = NO;
        _cornerRadius    = 0.0;
        _videoAutoplay = NO;
        _videoLoop     = NO;
        _videoControls = YES;
        _children      = [NSMutableArray array];
    }
    return self;
}

+ (nullable instancetype)fromDictionary:(nonnull NSDictionary*)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;

    MobNode *node = [[MobNode alloc] init];

    // Node type
    NSString *typeStr = dict[@"type"];
    if ([typeStr isKindOfClass:[NSString class]]) {
        node.nodeType = [self nodeTypeFromString:typeStr];
    }

    // Props dictionary
    NSDictionary *props = dict[@"props"];
    if ([props isKindOfClass:[NSDictionary class]]) {
        [self applyProps:props toNode:node];
    }

    // Children
    NSArray *children = dict[@"children"];
    if ([children isKindOfClass:[NSArray class]]) {
        for (id childDict in children) {
            if ([childDict isKindOfClass:[NSDictionary class]]) {
                MobNode *child = [MobNode fromDictionary:childDict];
                if (child) {
                    [node.children addObject:child];
                }
            }
        }
    }

    return node;
}

+ (MobNodeType)nodeTypeFromString:(NSString *)str {
    static NSDictionary *map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"column":        @(MobNodeTypeColumn),
            @"row":           @(MobNodeTypeRow),
            @"label":         @(MobNodeTypeLabel),
            @"button":        @(MobNodeTypeButton),
            @"scroll":        @(MobNodeTypeScroll),
            @"box":           @(MobNodeTypeBox),
            @"divider":       @(MobNodeTypeDivider),
            @"spacer":        @(MobNodeTypeSpacer),
            @"progress":      @(MobNodeTypeProgress),
            @"text_field":    @(MobNodeTypeTextField),
            @"toggle":        @(MobNodeTypeToggle),
            @"slider":        @(MobNodeTypeSlider),
            @"image":         @(MobNodeTypeImage),
            @"lazy_list":     @(MobNodeTypeLazyList),
            @"tab_bar":       @(MobNodeTypeTabBar),
            @"video":         @(MobNodeTypeVideo),
            @"camera_preview": @(MobNodeTypeCameraPreview),
            @"web_view":      @(MobNodeTypeWebView),
            @"native_view":   @(MobNodeTypeNativeView),
            @"icon":          @(MobNodeTypeIcon),
        };
    });
    NSNumber *typeNum = map[str];
    return typeNum ? (MobNodeType)typeNum.integerValue : MobNodeTypeColumn;
}

+ (void)applyProps:(NSDictionary *)props toNode:(MobNode *)node {
    // Text
    id text = props[@"text"];
    if ([text isKindOfClass:[NSString class]]) node.text = text;

    // Colors (hex strings like "#FF0000")
    id bgColor = props[@"background_color"];
    if ([bgColor isKindOfClass:[NSString class]]) node.backgroundColor = [self colorFromHex:bgColor];

    id textColor = props[@"text_color"];
    if ([textColor isKindOfClass:[NSString class]]) node.textColor = [self colorFromHex:textColor];

    // Padding
    id padding = props[@"padding"];
    if ([padding isKindOfClass:[NSNumber class]]) node.padding = [padding doubleValue];

    // Text size
    id textSize = props[@"text_size"];
    if ([textSize isKindOfClass:[NSNumber class]]) node.textSize = [textSize doubleValue];

    // Font weight
    id fontWeight = props[@"font_weight"];
    if ([fontWeight isKindOfClass:[NSString class]]) node.fontWeight = fontWeight;

    // Text align
    id textAlign = props[@"text_align"];
    if ([textAlign isKindOfClass:[NSString class]]) node.textAlign = textAlign;

    // Italic
    id italic = props[@"italic"];
    if ([italic isKindOfClass:[NSNumber class]]) node.italic = [italic boolValue];

    // Corner radius
    id cornerRadius = props[@"corner_radius"];
    if ([cornerRadius isKindOfClass:[NSNumber class]]) node.cornerRadius = [cornerRadius doubleValue];

    // Fill width
    id fillWidth = props[@"fill_width"];
    if ([fillWidth isKindOfClass:[NSNumber class]]) node.fillWidth = [fillWidth boolValue];

    // Accessibility ID
    id accessibilityId = props[@"accessibility_id"];
    if ([accessibilityId isKindOfClass:[NSString class]]) node.accessibilityId = accessibilityId;
}

+ (UIColor *)colorFromHex:(NSString *)hex {
    if (![hex hasPrefix:@"#"]) return nil;
    NSString *clean = [hex substringFromIndex:1];
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    [scanner scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb>>16)&0xFF)/255.0 green:((rgb>>8)&0xFF)/255.0 blue:(rgb&0xFF)/255.0 alpha:1.0];
}

@end
