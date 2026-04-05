// mob_nif.m — Mob UI NIF for iOS (UIKit).
// Module name: mob_nif
//
// NIF functions mirror mob_nif.c exactly so the same Elixir library works
// on both Android and iOS without changes.
//
// Threading: UIKit calls MUST run on the main thread. All NIF calls that
// touch UIKit use dispatch_sync(dispatch_get_main_queue(), ^{...}).
// BEAM runs on a background thread (see mob_beam.m), so this is safe.
//
// Memory: UIView* objects are stored as void* using CFBridgingRetain (+1
// manual retain outside ARC). The NIF resource destructor balances with
// CFRelease. MobTapTarget objects are stored the same way.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <stdint.h>
#include <string.h>
#include "erl_nif.h"
#include "mob_beam.h"

#define LOG_TAG "MobNIF"
#define LOGI(...) NSLog(@"[MobNIF] " __VA_ARGS__)
#define LOGE(...) NSLog(@"[MobNIF][ERROR] " __VA_ARGS__)

// ── View resource ─────────────────────────────────────────────────────────────

typedef enum { VTYPE_GENERIC = 0, VTYPE_STACK = 1, VTYPE_SCROLL = 2 } VType;

typedef struct {
    CFTypeRef view;         // retained UIView* (CFBridgingRetain)
    CFTypeRef stack_inner;  // retained inner UIStackView* (VTYPE_SCROLL only)
    CFTypeRef tap_target;   // retained MobTapTarget* (when has_tap_pid)
    VType     vtype;
    ErlNifPid tap_pid;
    int       has_tap_pid;
} ViewRes;

static ErlNifResourceType* view_res_type = NULL;

// ── MobTapTarget ─────────────────────────────────────────────────────────────

@interface MobTapTarget : NSObject
@property (nonatomic) ViewRes* res;
- (void)handleTap:(UIGestureRecognizer*)recognizer;
@end

@implementation MobTapTarget
- (void)handleTap:(UIGestureRecognizer*)recognizer {
    ViewRes* r = self.res;
    if (!r || !r->has_tap_pid) return;
    ErlNifEnv* env = enif_alloc_env();
    ERL_NIF_TERM view_term = enif_make_resource(env, r);
    ERL_NIF_TERM msg = enif_make_tuple2(env,
        enif_make_atom(env, "tap"),
        view_term);
    enif_send(NULL, &r->tap_pid, env, msg);
    enif_free_env(env);
}
@end

// ── Helpers ───────────────────────────────────────────────────────────────────

static int get_string(ErlNifEnv* env, ERL_NIF_TERM term, char* buf, size_t size) {
    ErlNifBinary bin;
    if (enif_inspect_binary(env, term, &bin)) {
        size_t len = bin.size < size - 1 ? bin.size : size - 1;
        memcpy(buf, bin.data, len);
        buf[len] = 0;
        return 1;
    }
    return enif_get_string(env, term, buf, size, ERL_NIF_UTF8) > 0;
}

static UIColor* color_from_argb(long argb) {
    CGFloat a = ((argb >> 24) & 0xFF) / 255.0;
    CGFloat r = ((argb >> 16) & 0xFF) / 255.0;
    CGFloat g = ((argb >>  8) & 0xFF) / 255.0;
    CGFloat b = ((argb >>  0) & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

// ── Resource destructor ───────────────────────────────────────────────────────

static void view_destructor(ErlNifEnv* env, void* ptr) {
    ViewRes* res = (ViewRes*)ptr;
    if (res->view)       CFRelease(res->view);
    if (res->stack_inner) CFRelease(res->stack_inner);
    if (res->tap_target)  CFRelease(res->tap_target);
}

// ── Helper: wrap a UIView into an Erlang resource ────────────────────────────

static ERL_NIF_TERM make_view(ErlNifEnv* env, UIView* view, VType vtype) {
    ViewRes* res = enif_alloc_resource(view_res_type, sizeof(ViewRes));
    res->view        = CFBridgingRetain(view);
    res->stack_inner = NULL;
    res->tap_target  = NULL;
    res->vtype       = vtype;
    res->has_tap_pid = 0;
    ERL_NIF_TERM term = enif_make_resource(env, res);
    enif_release_resource(res);
    return term;
}

// ── NIF: log/1 ────────────────────────────────────────────────────────────────

static ERL_NIF_TERM nif_log(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char buf[512] = {0};
    if (!get_string(env, argv[0], buf, sizeof(buf)))
        return enif_make_badarg(env);
    NSLog(@"[mob] %s", buf);
    return enif_make_atom(env, "ok");
}

// ── NIF: create_column/0 ─────────────────────────────────────────────────────

static ERL_NIF_TERM nif_create_column(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    __block ERL_NIF_TERM result;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIStackView* sv = [[UIStackView alloc] init];
        sv.axis         = UILayoutConstraintAxisVertical;
        sv.alignment    = UIStackViewAlignmentFill;
        sv.distribution = UIStackViewDistributionFill;
        sv.translatesAutoresizingMaskIntoConstraints = NO;
        result = enif_make_tuple2(env,
            enif_make_atom(env, "ok"),
            make_view(env, sv, VTYPE_STACK));
    });
    return result;
}

// ── NIF: create_row/0 ────────────────────────────────────────────────────────

static ERL_NIF_TERM nif_create_row(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    __block ERL_NIF_TERM result;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIStackView* sv = [[UIStackView alloc] init];
        sv.axis         = UILayoutConstraintAxisHorizontal;
        sv.alignment    = UIStackViewAlignmentFill;
        sv.distribution = UIStackViewDistributionFill;
        sv.translatesAutoresizingMaskIntoConstraints = NO;
        result = enif_make_tuple2(env,
            enif_make_atom(env, "ok"),
            make_view(env, sv, VTYPE_STACK));
    });
    return result;
}

// ── NIF: create_label/1 ──────────────────────────────────────────────────────

static ERL_NIF_TERM nif_create_label(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char text[512] = {0};
    if (!get_string(env, argv[0], text, sizeof(text)))
        return enif_make_badarg(env);

    NSString* ns_text = [NSString stringWithUTF8String:text];
    __block ERL_NIF_TERM result;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UILabel* label = [[UILabel alloc] init];
        label.text          = ns_text;
        label.numberOfLines = 0;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        result = enif_make_tuple2(env,
            enif_make_atom(env, "ok"),
            make_view(env, label, VTYPE_GENERIC));
    });
    return result;
}

// ── NIF: create_button/1 ─────────────────────────────────────────────────────

static ERL_NIF_TERM nif_create_button(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char text[256] = {0};
    if (!get_string(env, argv[0], text, sizeof(text)))
        return enif_make_badarg(env);

    NSString* ns_text = [NSString stringWithUTF8String:text];
    __block ERL_NIF_TERM result;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIButton* btn = [UIButton buttonWithType:UIButtonTypeSystem];
        [btn setTitle:ns_text forState:UIControlStateNormal];
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        result = enif_make_tuple2(env,
            enif_make_atom(env, "ok"),
            make_view(env, btn, VTYPE_GENERIC));
    });
    return result;
}

// ── NIF: create_scroll/0 ─────────────────────────────────────────────────────

static ERL_NIF_TERM nif_create_scroll(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    __block ERL_NIF_TERM result;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIScrollView* sv = [[UIScrollView alloc] init];
        sv.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView* inner = [[UIStackView alloc] init];
        inner.axis         = UILayoutConstraintAxisVertical;
        inner.alignment    = UIStackViewAlignmentFill;
        inner.distribution = UIStackViewDistributionEqualSpacing;
        inner.translatesAutoresizingMaskIntoConstraints = NO;
        [sv addSubview:inner];

        // Pin inner stack to scroll view's content layout guide
        UILayoutGuide* content = sv.contentLayoutGuide;
        UILayoutGuide* frame   = sv.frameLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [inner.topAnchor    constraintEqualToAnchor:content.topAnchor],
            [inner.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [inner.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [inner.bottomAnchor  constraintEqualToAnchor:content.bottomAnchor],
            [inner.widthAnchor   constraintEqualToAnchor:frame.widthAnchor],
        ]];

        ViewRes* res       = enif_alloc_resource(view_res_type, sizeof(ViewRes));
        res->view          = CFBridgingRetain(sv);
        res->stack_inner   = CFBridgingRetain(inner);
        res->tap_target    = NULL;
        res->vtype         = VTYPE_SCROLL;
        res->has_tap_pid   = 0;
        ERL_NIF_TERM term  = enif_make_resource(env, res);
        enif_release_resource(res);
        result = enif_make_tuple2(env, enif_make_atom(env, "ok"), term);
    });
    return result;
}

// ── NIF: add_child/2 ─────────────────────────────────────────────────────────

static ERL_NIF_TERM nif_add_child(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    ViewRes *parent, *child;
    if (!enif_get_resource(env, argv[0], view_res_type, (void**)&parent) ||
        !enif_get_resource(env, argv[1], view_res_type, (void**)&child))
        return enif_make_badarg(env);

    dispatch_sync(dispatch_get_main_queue(), ^{
        UIView* child_view = (__bridge UIView*)child->view;

        // Children in a stack view should use their natural (intrinsic) height,
        // not stretch to fill the parent — mirrors Android LinearLayout wrap_content.
        [child_view setContentHuggingPriority:UILayoutPriorityRequired
                                      forAxis:UILayoutConstraintAxisVertical];
        [child_view setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                    forAxis:UILayoutConstraintAxisVertical];

        if (parent->vtype == VTYPE_SCROLL) {
            UIStackView* inner = (__bridge UIStackView*)parent->stack_inner;
            [inner addArrangedSubview:child_view];
        } else if (parent->vtype == VTYPE_STACK) {
            UIStackView* sv = (__bridge UIStackView*)parent->view;
            [sv addArrangedSubview:child_view];
        } else {
            UIView* parent_view = (__bridge UIView*)parent->view;
            [parent_view addSubview:child_view];
        }
    });
    return enif_make_atom(env, "ok");
}

// ── NIF: remove_child/1 ──────────────────────────────────────────────────────

static ERL_NIF_TERM nif_remove_child(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    ViewRes* res;
    if (!enif_get_resource(env, argv[0], view_res_type, (void**)&res))
        return enif_make_badarg(env);

    dispatch_sync(dispatch_get_main_queue(), ^{
        UIView* v = (__bridge UIView*)res->view;
        if ([v.superview isKindOfClass:[UIStackView class]]) {
            [(UIStackView*)v.superview removeArrangedSubview:v];
        }
        [v removeFromSuperview];
    });
    return enif_make_atom(env, "ok");
}

// ── NIF: set_text/2 ──────────────────────────────────────────────────────────

static ERL_NIF_TERM nif_set_text(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    ViewRes* res;
    char text[512] = {0};
    if (!enif_get_resource(env, argv[0], view_res_type, (void**)&res) ||
        !get_string(env, argv[1], text, sizeof(text)))
        return enif_make_badarg(env);

    NSString* ns_text = [NSString stringWithUTF8String:text];
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIView* v = (__bridge UIView*)res->view;
        if ([v isKindOfClass:[UILabel class]]) {
            ((UILabel*)v).text = ns_text;
        } else if ([v isKindOfClass:[UIButton class]]) {
            [(UIButton*)v setTitle:ns_text forState:UIControlStateNormal];
        }
    });
    return enif_make_atom(env, "ok");
}

// ── NIF: set_text_size/2 ─────────────────────────────────────────────────────

static ERL_NIF_TERM nif_set_text_size(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    ViewRes* res;
    double sz;
    if (!enif_get_resource(env, argv[0], view_res_type, (void**)&res))
        return enif_make_badarg(env);
    if (!enif_get_double(env, argv[1], &sz)) {
        int ival;
        if (!enif_get_int(env, argv[1], &ival))
            return enif_make_badarg(env);
        sz = (double)ival;
    }

    dispatch_sync(dispatch_get_main_queue(), ^{
        UIView* v = (__bridge UIView*)res->view;
        if ([v isKindOfClass:[UILabel class]]) {
            ((UILabel*)v).font = [UIFont systemFontOfSize:(CGFloat)sz];
        } else if ([v isKindOfClass:[UIButton class]]) {
            ((UIButton*)v).titleLabel.font = [UIFont systemFontOfSize:(CGFloat)sz];
        }
    });
    return enif_make_atom(env, "ok");
}

// ── NIF: set_text_color/2 ────────────────────────────────────────────────────

static ERL_NIF_TERM nif_set_text_color(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    ViewRes* res;
    long color;
    if (!enif_get_resource(env, argv[0], view_res_type, (void**)&res) ||
        !enif_get_long(env, argv[1], &color))
        return enif_make_badarg(env);

    UIColor* uicolor = color_from_argb(color);
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIView* v = (__bridge UIView*)res->view;
        if ([v isKindOfClass:[UILabel class]]) {
            ((UILabel*)v).textColor = uicolor;
        } else if ([v isKindOfClass:[UIButton class]]) {
            [(UIButton*)v setTitleColor:uicolor forState:UIControlStateNormal];
        }
    });
    return enif_make_atom(env, "ok");
}

// ── NIF: set_background_color/2 ──────────────────────────────────────────────

static ERL_NIF_TERM nif_set_background_color(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    ViewRes* res;
    long color;
    if (!enif_get_resource(env, argv[0], view_res_type, (void**)&res) ||
        !enif_get_long(env, argv[1], &color))
        return enif_make_badarg(env);

    UIColor* uicolor = color_from_argb(color);
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIView* v = (__bridge UIView*)res->view;
        v.backgroundColor = uicolor;
    });
    return enif_make_atom(env, "ok");
}

// ── NIF: set_padding/2 ───────────────────────────────────────────────────────

static ERL_NIF_TERM nif_set_padding(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    ViewRes* res;
    int dp;
    if (!enif_get_resource(env, argv[0], view_res_type, (void**)&res) ||
        !enif_get_int(env, argv[1], &dp))
        return enif_make_badarg(env);

    dispatch_sync(dispatch_get_main_queue(), ^{
        UIView* v = (__bridge UIView*)res->view;
        if ([v isKindOfClass:[UIStackView class]]) {
            UIStackView* sv = (UIStackView*)v;
            sv.layoutMargins = UIEdgeInsetsMake(dp, dp, dp, dp);
            sv.layoutMarginsRelativeArrangement = YES;
        }
    });
    return enif_make_atom(env, "ok");
}

// ── NIF: on_tap/2 ─────────────────────────────────────────────────────────────

static ERL_NIF_TERM nif_on_tap(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    ViewRes* res;
    ErlNifPid pid;
    if (!enif_get_resource(env, argv[0], view_res_type, (void**)&res) ||
        !enif_get_local_pid(env, argv[1], &pid))
        return enif_make_badarg(env);

    res->tap_pid = pid;

    dispatch_sync(dispatch_get_main_queue(), ^{
        UIView* v = (__bridge UIView*)res->view;

        if (!res->has_tap_pid) {
            // First time: create the tap target and attach recognizer.
            enif_keep_resource(res);
            res->has_tap_pid = 1;

            MobTapTarget* target = [[MobTapTarget alloc] init];
            target.res = res;
            res->tap_target = CFBridgingRetain(target);

            UITapGestureRecognizer* gr = [[UITapGestureRecognizer alloc]
                initWithTarget:target action:@selector(handleTap:)];
            v.userInteractionEnabled = YES;
            [v addGestureRecognizer:gr];
        } else {
            // Update the pid on the existing target.
            MobTapTarget* target = (__bridge MobTapTarget*)res->tap_target;
            target.res = res;  // res->tap_pid was already updated above
        }
    });
    return enif_make_atom(env, "ok");
}

// ── NIF: set_root/1 ──────────────────────────────────────────────────────────

static ERL_NIF_TERM nif_set_root(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    ViewRes* res;
    if (!enif_get_resource(env, argv[0], view_res_type, (void**)&res))
        return enif_make_badarg(env);

    dispatch_sync(dispatch_get_main_queue(), ^{
        if (!g_root_vc) { LOGE(@"set_root: g_root_vc is nil"); return; }

        UIView* root = g_root_vc.view;
        UIView* new_view = (__bridge UIView*)res->view;

        // Remove any existing subviews
        for (UIView* sv in root.subviews.copy) {
            [sv removeFromSuperview];
        }

        // Pin leading/trailing/top to fill screen width and start at top.
        // No bottom constraint — the column wraps its content height,
        // matching Android LinearLayout's wrap_content default.
        new_view.translatesAutoresizingMaskIntoConstraints = NO;
        [root addSubview:new_view];
        UILayoutGuide* safe = root.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [new_view.topAnchor     constraintEqualToAnchor:safe.topAnchor],
            [new_view.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
            [new_view.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        ]];
        LOGI(@"set_root: view installed %@", new_view);
    });
    return enif_make_atom(env, "ok");
}

// ── NIF table & load ─────────────────────────────────────────────────────────

static ErlNifFunc nif_funcs[] = {
    {"log",                  1, nif_log,                  0},
    {"create_column",        0, nif_create_column,        0},
    {"create_row",           0, nif_create_row,           0},
    {"create_label",         1, nif_create_label,         0},
    {"create_button",        1, nif_create_button,        0},
    {"create_scroll",        0, nif_create_scroll,        0},
    {"add_child",            2, nif_add_child,            0},
    {"remove_child",         1, nif_remove_child,         0},
    {"set_text",             2, nif_set_text,             0},
    {"set_text_size",        2, nif_set_text_size,        0},
    {"set_text_color",       2, nif_set_text_color,       0},
    {"set_background_color", 2, nif_set_background_color, 0},
    {"set_padding",          2, nif_set_padding,          0},
    {"on_tap",               2, nif_on_tap,               0},
    {"set_root",             1, nif_set_root,             0},
};

static int nif_load(ErlNifEnv* env, void** priv, ERL_NIF_TERM info) {
    LOGI(@"nif_load: initialising mob_nif (iOS)");
    view_res_type = enif_open_resource_type(env, NULL, "mob_view",
        view_destructor, ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER, NULL);
    if (!view_res_type) {
        LOGE(@"nif_load: enif_open_resource_type failed");
        return -1;
    }
    LOGI(@"nif_load: mob_nif ready");
    return 0;
}

ERL_NIF_INIT(mob_nif, nif_funcs, nif_load, NULL, NULL, NULL)
