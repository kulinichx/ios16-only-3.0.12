//
//  DOSupporterLicenseUI.h
//  Dopamine
//

#import <UIKit/UIKit.h>
#import "DOSupporterLicense.h"
#import "DOSceneDelegate.h"
#import "DOUIManager.h"

static inline void DORHShowSupporterMessage(UIViewController *presenter,
                                             NSString *title,
                                             NSString *message)
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Supporter_OK")
                                             style:UIAlertActionStyleDefault
                                           handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static inline void DORHShowSupporterLicenseChange(UIViewController *presenter,
                                                   NSString *title,
                                                   NSString *message)
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Supporter_Apply_Now")
                                             style:UIAlertActionStyleDefault
                                           handler:^(__kindof UIAlertAction *action) {
        [DOSceneDelegate relaunch];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Supporter_OK")
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static inline void DORHPresentSupporterDiagnostics(UIViewController *presenter)
{
    UIAlertController *consent =
        [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Supporter_Diagnostics_Consent_Title")
                                            message:DOLocalizedString(@"Supporter_Diagnostics_Consent_Message")
                                     preferredStyle:UIAlertControllerStyleAlert];
    [consent addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Supporter_Run_Diagnostics")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__kindof UIAlertAction *action) {
        NSDictionary<NSString *, id> *hardware = DORHSupporterHardwareIdentityProbe();
        NSDictionary<NSString *, id> *key = DORHSupporterDeviceKeyProbe();

        NSString *hardwareStatus = [hardware[@"available"] boolValue]
            ? DOLocalizedString(@"Supporter_Diagnostics_Available")
            : DOLocalizedString(@"Supporter_Diagnostics_Unavailable");
        NSString *keyStatus = [key[@"available"] boolValue]
            ? DOLocalizedString(@"Supporter_Diagnostics_Available")
            : DOLocalizedString(@"Supporter_Diagnostics_Unavailable");
        NSString *keyState = [key[@"available"] boolValue]
            ? ([key[@"created"] boolValue]
                ? DOLocalizedString(@"Supporter_Key_State_Created")
                : DOLocalizedString(@"Supporter_Key_State_Reused"))
            : [NSString stringWithFormat:@"%@ (%@, %@)",
                DOLocalizedString(@"Supporter_Diagnostics_Failed"),
                key[@"stage"] ?: @"unknown",
                key[@"error_code"] ?: @(-1)];
        NSString *signatureStatus = [key[@"signature_self_test"] boolValue]
            ? DOLocalizedString(@"Supporter_Diagnostics_Passed")
            : DOLocalizedString(@"Supporter_Diagnostics_Failed");
        NSString *message = [NSString stringWithFormat:
            DOLocalizedString(@"Supporter_Diagnostics_Result_Format"),
            hardwareStatus,
            hardware[@"algorithm"] ?: @"rh-hw-v1",
            keyStatus,
            keyState,
            signatureStatus];
        DORHShowSupporterMessage(presenter,
            DOLocalizedString(@"Supporter_Advanced_Diagnostics"), message);
    }]];
    [consent addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [presenter presentViewController:consent animated:YES completion:nil];
}

static inline void DORHPresentSupporterLicense(UIViewController *presenter)
{
    NSDictionary<NSString *, id> *info = DORHSupporterCurrentLicenseInfo();
    NSString *supporterID = [info[@"sid"] isKindOfClass:NSString.class] ? info[@"sid"] : nil;
    NSString *status = supporterID.length > 0
        ? DOLocalizedString(@"Supporter_Status_Verified")
        : DOLocalizedString(@"Supporter_Status_Not_Activated");
    NSString *deviceCode = DORHSupporterDeviceCode();
    NSString *message = [NSString stringWithFormat:
        DOLocalizedString(@"Supporter_Status_Message_Format"),
        status,
        deviceCode.length > 0 ? deviceCode : DOLocalizedString(@"Supporter_Unavailable")];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Supporter_Title")
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak UIViewController *weakPresenter = presenter;

    UIAlertAction *copyAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Supporter_Copy_Device_Code")
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(__kindof UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = deviceCode;
        DORHShowSupporterMessage(weakPresenter,
            DOLocalizedString(@"Supporter_Device_Code_Copied"),
            DOLocalizedString(@"Supporter_Device_Code_Copied_Message"));
    }];
    copyAction.enabled = deviceCode.length > 0;
    [alert addAction:copyAction];

    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Supporter_Bind_This_Device")
                                             style:UIAlertActionStyleDefault
                                           handler:^(__kindof UIAlertAction *action) {
        NSString *challenge = UIPasteboard.generalPasteboard.string ?: @"";
        NSString *failureStage = nil;
        NSInteger failureCode = 0;
        NSData *proof = DORHSupporterCreateRHP1Proof(
            [challenge dataUsingEncoding:NSUTF8StringEncoding], &failureStage, &failureCode);
        NSString *proofText = proof ? [[NSString alloc] initWithData:proof encoding:NSUTF8StringEncoding] : nil;
        if (proofText.length == 0) {
            NSString *failure = [NSString stringWithFormat:
                DOLocalizedString(@"Supporter_Device_Proof_Failed_Format"),
                failureStage ?: @"unknown", (long)failureCode];
            DORHShowSupporterMessage(weakPresenter,
                DOLocalizedString(@"Supporter_Device_Proof_Failed"), failure);
            return;
        }
        UIPasteboard.generalPasteboard.string = proofText;
        DORHShowSupporterMessage(weakPresenter,
            DOLocalizedString(@"Supporter_Device_Proof_Ready"),
            DOLocalizedString(@"Supporter_Device_Proof_Ready_Message"));
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Supporter_Paste_License")
                                             style:UIAlertActionStyleDefault
                                           handler:^(__kindof UIAlertAction *action) {
        NSError *error = nil;
        if (DORHSupporterStoreLicenseCode(UIPasteboard.generalPasteboard.string ?: @"", &error)) {
            DORHShowSupporterLicenseChange(weakPresenter,
                DOLocalizedString(@"Supporter_Activated"),
                DOLocalizedString(@"Supporter_Activated_Message"));
        } else {
            DORHShowSupporterMessage(weakPresenter,
                DOLocalizedString(@"Supporter_Invalid_License"),
                error.localizedDescription ?: DOLocalizedString(@"Supporter_Invalid_License_Fallback"));
        }
    }]];

    if (supporterID.length > 0) {
        [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Supporter_Remove_License")
                                                 style:UIAlertActionStyleDestructive
                                               handler:^(__kindof UIAlertAction *action) {
            if (!DORHSupporterRemoveLicense()) {
                DORHShowSupporterMessage(weakPresenter,
                    DOLocalizedString(@"Supporter_Remove_Failed"),
                    DOLocalizedString(@"Supporter_Remove_Failed_Message"));
                return;
            }
            DORHShowSupporterLicenseChange(weakPresenter,
                DOLocalizedString(@"Supporter_Removed"),
                DOLocalizedString(@"Supporter_Removed_Message"));
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Cancel")
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Supporter_Advanced_Diagnostics")
                                             style:UIAlertActionStyleDefault
                                           handler:^(__kindof UIAlertAction *action) {
        DORHPresentSupporterDiagnostics(weakPresenter);
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
