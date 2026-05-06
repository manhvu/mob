// DalaNode.m — Dala UI tree node implementation.

#import "DalaNode.h"
#import <math.h>

@implementation DalaNode

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
        _gap             = 0.0;
        _disabled        = NO;
        _videoAutoplay = NO;
        _videoLoop     = NO;
        _videoControls = YES;
        _children      = [NSMutableArray array];
        _nodeId        = [[NSUUID UUID] UUIDString];  // Unique ID for SwiftUI ForEach
    }
    return self;
}

+ (nullable instancetype)fromDictionary:(nonnull NSDictionary*)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;

    DalaNode *node = [[DalaNode alloc] init];

    // Generate unique ID (can be overridden by props if needed for debugging)
    node.nodeId = [[NSUUID UUID] UUIDString];

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
                DalaNode *child = [DalaNode fromDictionary:childDict];
                if (child) {
                    [node.children addObject:child];
                }
            }
        }
    }

    return node;
}

+ (DalaNodeType)nodeTypeFromString:(NSString *)str {
    static NSDictionary *map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            @"column":        @(DalaNodeTypeColumn),
            @"row":           @(DalaNodeTypeRow),
            @"label":         @(DalaNodeTypeLabel),
            @"text":          @(DalaNodeTypeLabel),
            @"button":        @(DalaNodeTypeButton),
            @"scroll":        @(DalaNodeTypeScroll),
            @"box":           @(DalaNodeTypeBox),
            @"divider":       @(DalaNodeTypeDivider),
            @"spacer":        @(DalaNodeTypeSpacer),
            @"progress":      @(DalaNodeTypeProgress),
            @"progress_bar":  @(DalaNodeTypeProgress),
            @"text_field":    @(DalaNodeTypeTextField),
            @"toggle":        @(DalaNodeTypeToggle),
            @"switch":        @(DalaNodeTypeToggle),
            @"slider":        @(DalaNodeTypeSlider),
            @"image":         @(DalaNodeTypeImage),
            @"lazy_list":     @(DalaNodeTypeLazyList),
            @"list":          @(DalaNodeTypeLazyList),
            @"tab_bar":       @(DalaNodeTypeTabBar),
            @"video":         @(DalaNodeTypeVideo),
            @"camera_preview": @(DalaNodeTypeCameraPreview),
            @"web_view":      @(DalaNodeTypeWebView),
            @"webview":       @(DalaNodeTypeWebView),
            @"native_view":   @(DalaNodeTypeNativeView),
            @"icon":          @(DalaNodeTypeIcon),
        };
    });
    NSNumber *typeNum = map[str];
return typeNum ? (DalaNodeType)typeNum.integerValue : DalaNodeTypeColumn;
}

+ (void)applyProps:(NSDictionary *)props toNode:(DalaNode *)node {
    // Text
    id text = props[@"text"];
    if ([text isKindOfClass:[NSString class]]) node.text = text;

    // Colors (hex strings like "#FF0000")
    id bgColor = props[@"background_color"];
    if ([bgColor isKindOfClass:[NSString class]]) node.backgroundColor = [self colorFromHex:bgColor];

    // Also accept "background" as an alias for background_color
    id bgAlias = props[@"background"];
    if ([bgAlias isKindOfClass:[NSString class]] && !bgColor) node.backgroundColor = [self colorFromHex:bgAlias];

    id textColor = props[@"text_color"];
    if ([textColor isKindOfClass:[NSString class]]) node.textColor = [self colorFromHex:textColor];

    // Padding
    id padding = props[@"padding"];
    if ([padding isKindOfClass:[NSNumber class]]) node.padding = [padding doubleValue];

    id paddingTop = props[@"padding_top"];
    if ([paddingTop isKindOfClass:[NSNumber class]]) node.paddingTop = [paddingTop doubleValue];

    id paddingRight = props[@"padding_right"];
    if ([paddingRight isKindOfClass:[NSNumber class]]) node.paddingRight = [paddingRight doubleValue];

    id paddingBottom = props[@"padding_bottom"];
    if ([paddingBottom isKindOfClass:[NSNumber class]]) node.paddingBottom = [paddingBottom doubleValue];

    id paddingLeft = props[@"padding_left"];
    if ([paddingLeft isKindOfClass:[NSNumber class]]) node.paddingLeft = [paddingLeft doubleValue];

    // Text size
    id textSize = props[@"text_size"];
    if ([textSize isKindOfClass:[NSNumber class]]) node.textSize = [textSize doubleValue];

    // Font weight
    id fontWeight = props[@"font_weight"];
    if ([fontWeight isKindOfClass:[NSString class]]) node.fontWeight = fontWeight;

    // Font family
    id fontFamily = props[@"font_family"];
    if ([fontFamily isKindOfClass:[NSString class]]) node.fontFamily = fontFamily;

    // Text align
    id textAlign = props[@"text_align"];
    if ([textAlign isKindOfClass:[NSString class]]) node.textAlign = textAlign;

    // Italic
    id italic = props[@"italic"];
    if ([italic isKindOfClass:[NSNumber class]]) node.italic = [italic boolValue];

    // Line height
    id lineHeight = props[@"line_height"];
    if ([lineHeight isKindOfClass:[NSNumber class]]) node.lineHeight = [lineHeight doubleValue];

    // Letter spacing
    id letterSpacing = props[@"letter_spacing"];
    if ([letterSpacing isKindOfClass:[NSNumber class]]) node.letterSpacing = [letterSpacing doubleValue];

    // Corner radius
    id cornerRadius = props[@"corner_radius"];
    if ([cornerRadius isKindOfClass:[NSNumber class]]) node.cornerRadius = [cornerRadius doubleValue];

    // Fill width
    id fillWidth = props[@"fill_width"];
    if ([fillWidth isKindOfClass:[NSNumber class]]) node.fillWidth = [fillWidth boolValue];

    // Gap (spacing between children in column/row)
    id gap = props[@"gap"];
    if ([gap isKindOfClass:[NSNumber class]]) node.gap = [gap doubleValue];

    // Disabled
    id disabled = props[@"disabled"];
    if ([disabled isKindOfClass:[NSNumber class]]) node.disabled = [disabled boolValue];

    // Border
    id borderColor = props[@"border_color"];
    if ([borderColor isKindOfClass:[NSString class]]) node.borderColor = [self colorFromHex:borderColor];

    id borderWidth = props[@"border_width"];
    if ([borderWidth isKindOfClass:[NSNumber class]]) node.borderWidth = [borderWidth doubleValue];

    // Accessibility ID
    id accessibilityId = props[@"accessibility_id"];
    if ([accessibilityId isKindOfClass:[NSString class]]) node.accessibilityId = accessibilityId;

    // ── Component-specific props ─────────────────────────────────────────

    // Divider
    id thickness = props[@"thickness"];
    if ([thickness isKindOfClass:[NSNumber class]]) node.thickness = [thickness doubleValue];

    id color = props[@"color"];
    if ([color isKindOfClass:[NSString class]]) node.color = [self colorFromHex:color];

    // Spacer
    id fixedSize = props[@"fixed_size"];
    if ([fixedSize isKindOfClass:[NSNumber class]]) node.fixedSize = [fixedSize doubleValue];

    // Scroll axis
    id axis = props[@"axis"];
    if ([axis isKindOfClass:[NSString class]]) node.axis = axis;

    id horizontal = props[@"horizontal"];
    if ([horizontal isKindOfClass:[NSNumber class]] && [horizontal boolValue]) node.axis = @"horizontal";

    id showIndicator = props[@"show_indicator"];
    if ([showIndicator isKindOfClass:[NSNumber class]]) node.showIndicator = [showIndicator boolValue];

    // Progress / Slider value
    id value = props[@"value"];
    if ([value isKindOfClass:[NSNumber class]]) node.value = [value doubleValue];

    id progress = props[@"progress"];
    if ([progress isKindOfClass:[NSNumber class]]) node.value = [progress doubleValue];

    id minValue = props[@"min_value"];
    if ([minValue isKindOfClass:[NSNumber class]]) node.minValue = [minValue doubleValue];

    id maxValue = props[@"max_value"];
    if ([maxValue isKindOfClass:[NSNumber class]]) node.maxValue = [maxValue doubleValue];

    // Toggle / Switch
    id checked = props[@"checked"];
    if ([checked isKindOfClass:[NSNumber class]]) node.checked = [checked boolValue];

    // Text field
    id placeholder = props[@"placeholder"];
    if ([placeholder isKindOfClass:[NSString class]]) node.placeholder = placeholder;

    id keyboardType = props[@"keyboard_type"];
    if ([keyboardType isKindOfClass:[NSString class]]) node.keyboardTypeStr = keyboardType;

    id returnKey = props[@"return_key"];
    if ([returnKey isKindOfClass:[NSString class]]) node.returnKeyStr = returnKey;

    // Image
    id src = props[@"src"];
    if ([src isKindOfClass:[NSString class]]) node.src = src;

    id contentMode = props[@"resize_mode"];
    if ([contentMode isKindOfClass:[NSString class]]) {
        if ([contentMode isEqualToString:@"fill"]) {
            node.contentModeStr = @"fill";
        } else if ([contentMode isEqualToString:@"stretch"]) {
            node.contentModeStr = @"stretch";
        } else {
            node.contentModeStr = @"fit";
        }
    }

    id fixedWidth = props[@"width"];
    if ([fixedWidth isKindOfClass:[NSNumber class]]) node.fixedWidth = [fixedWidth doubleValue];

    id fixedHeight = props[@"height"];
    if ([fixedHeight isKindOfClass:[NSNumber class]]) node.fixedHeight = [fixedHeight doubleValue];

    id placeholderColor = props[@"placeholder_color"];
    if ([placeholderColor isKindOfClass:[NSString class]]) node.placeholderColor = [self colorFromHex:placeholderColor];

    // Icon
    id iconName = props[@"name"];
    if ([iconName isKindOfClass:[NSString class]]) node.iconName = iconName;

    // Tab bar
    id tabDefs = props[@"tabs"];
    if ([tabDefs isKindOfClass:[NSArray class]]) node.tabDefs = tabDefs;

    id activeTab = props[@"active_tab"];
    if ([activeTab isKindOfClass:[NSString class]]) node.activeTab = activeTab;

    // Video
    id autoplay = props[@"autoplay"];
    if ([autoplay isKindOfClass:[NSNumber class]]) node.videoAutoplay = [autoplay boolValue];

    id loop = props[@"loop"];
    if ([loop isKindOfClass:[NSNumber class]]) node.videoLoop = [loop boolValue];

    id controls = props[@"controls"];
    if ([controls isKindOfClass:[NSNumber class]]) node.videoControls = [controls boolValue];

    // Camera preview
    id facing = props[@"facing"];
    if ([facing isKindOfClass:[NSString class]]) node.cameraFacing = facing;

    // WebView
    id webViewUrl = props[@"url"];
    if ([webViewUrl isKindOfClass:[NSString class]]) node.webViewUrl = webViewUrl;

    id webViewAllow = props[@"allow"];
    if ([webViewAllow isKindOfClass:[NSString class]]) node.webViewAllow = webViewAllow;

    id webViewShowUrl = props[@"show_url"];
    if ([webViewShowUrl isKindOfClass:[NSNumber class]]) node.webViewShowUrl = [webViewShowUrl boolValue];

    id webViewTitle = props[@"title"];
    if ([webViewTitle isKindOfClass:[NSString class]]) node.webViewTitle = webViewTitle;

    // Native view
    id nativeViewModule = props[@"module"];
    if ([nativeViewModule isKindOfClass:[NSString class]]) node.nativeViewModule = nativeViewModule;

    id nativeViewId = props[@"id"];
    if ([nativeViewId isKindOfClass:[NSString class]]) node.nativeViewId = nativeViewId;

    id nativeViewHandle = props[@"component_handle"];
    if ([nativeViewHandle isKindOfClass:[NSNumber class]]) node.nativeViewHandle = [nativeViewHandle intValue];

    node.nativeViewProps = props;
}

+ (UIColor *)colorFromHex:(NSString *)hex {
    if (![hex hasPrefix:@"#"]) return nil;
    NSString *clean = [hex substringFromIndex:1];

    // Validate hex string length (expect 6 characters: RRGGBB)
    if (clean.length != 6) {
        NSLog(@"[Dala] Invalid hex color: %@ (expected 6 chars, got %lu)", hex, (unsigned long)clean.length);
        return nil;
    }

    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    [scanner scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb>>16)&0xFF)/255.0 green:((rgb>>8)&0xFF)/255.0 blue:(rgb&0xFF)/255.0 alpha:1.0];
}

@end
