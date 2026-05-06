#import <Preferences/PSListController.h>

@interface VCPRootListController : PSListController
@end

@implementation VCPRootListController
- (id)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}
@end
