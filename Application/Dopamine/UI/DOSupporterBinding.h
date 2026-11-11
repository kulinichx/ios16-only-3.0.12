// Included by DOSupporterLicense.h after the RH1 signature verifier.
#pragma once

// Migration builds preserve unbound RH1 installs. Flip only after device testing.
#ifndef DORH_SUPPORTER_REQUIRE_BINDING
#define DORH_SUPPORTER_REQUIRE_BINDING 0
#endif

static NSString * const DORHSupporterBindingCertificateKey = @"BindingCertificate";
static NSString * const DORHSupporterBindingRequiredKey = @"BindingRequired";

static inline NSString *DORHSupporterSHA256(NSData *data)
{
    unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *text = [NSMutableString stringWithCapacity:64];
    for (NSUInteger i = 0; i < sizeof(digest); i++)
        [text appendFormat:@"%02X", digest[i]];
    return text;
}

static inline SecKeyRef DORHSupporterCopyExistingDevicePrivateKey(void)
{
    NSData *tag = [DORHSupporterDeviceKeyTag dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassKey,
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate,
        (__bridge id)kSecAttrTokenID: (__bridge id)kSecAttrTokenIDSecureEnclave,
        (__bridge id)kSecAttrApplicationTag: tag,
        (__bridge id)kSecReturnRef: @YES
    };
    CFTypeRef item = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &item);
    if (status != errSecSuccess || !item ||
        !DORHSupporterDeviceKeyIsSecureEnclaveP256PrivateKey((SecKeyRef)item)) {
        if (item) CFRelease(item);
        return NULL;
    }
    return (SecKeyRef)item;
}

static inline NSDictionary *DORHSupporterBindingCertificateInfo(NSString *certificate, NSError **error)
{
    if (![certificate isKindOfClass:NSString.class] || certificate.length > 4096) {
        if (error) *error = DORHSupporterLicenseError(20, @"Invalid binding certificate size");
        return nil;
    }
    NSArray<NSString *> *parts = [certificate componentsSeparatedByString:@"."];
    if (parts.count != 3 || ![parts[0] isEqualToString:@"RHB1"]) {
        if (error) *error = DORHSupporterLicenseError(21, @"Invalid binding certificate format");
        return nil;
    }
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"] invertedSet];
    for (NSString *part in @[parts[1], parts[2]]) {
        if (part.length == 0 || [part rangeOfCharacterFromSet:invalid].location != NSNotFound) {
            if (error) *error = DORHSupporterLicenseError(21, @"Invalid binding certificate encoding");
            return nil;
        }
    }
    NSData *payload = DORHSupporterDecodeBase64URL(parts[1]);
    NSData *signature = DORHSupporterDecodeBase64URL(parts[2]);
    if (payload.length == 0 || signature.length == 0) return nil;
    NSMutableData *message = [[@"DopamineRH-RHB1-Sign-v1" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    unsigned char separator = 0;
    [message appendBytes:&separator length:1];
    [message appendData:payload];
    SecKeyRef issuer = DORHSupporterCreatePublicKey();
    BOOL valid = issuer && SecKeyVerifySignature(issuer,
        kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
        (__bridge CFDataRef)message, (__bridge CFDataRef)signature, NULL);
    if (issuer) CFRelease(issuer);
    if (!valid) {
        if (error) *error = DORHSupporterLicenseError(22, @"Invalid binding certificate signature");
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:payload options:0 error:nil];
    if (![object isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *info = object;
    NSSet *keys = [NSSet setWithArray:@[@"v", @"product", @"sid", @"device", @"license_sha256",
        @"hardware_protocol", @"hardware_hash", @"key_fingerprint", @"issued_at"]];
    if (![[NSSet setWithArray:info.allKeys] isEqualToSet:keys]) return nil;
    for (NSString *key in @[@"product", @"sid", @"device", @"license_sha256", @"hardware_protocol", @"hardware_hash", @"key_fingerprint"])
        if (![info[key] isKindOfClass:NSString.class]) return nil;
    if (![info[@"v"] isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)info[@"v"]) == CFBooleanGetTypeID() ||
        [info[@"v"] doubleValue] != 1.0 ||
        ![info[@"product"] isEqualToString:@"DopamineRH"] ||
        ![info[@"hardware_protocol"] isEqualToString:@"rh-hw-v1"] ||
        [info[@"sid"] length] == 0 || [info[@"device"] length] == 0 ||
        !DORHSupporterIsUppercaseHexString(info[@"license_sha256"], 64) ||
        !DORHSupporterIsUppercaseHexString(info[@"hardware_hash"], 64) ||
        !DORHSupporterIsUppercaseHexString(info[@"key_fingerprint"], 64) ||
        ![info[@"issued_at"] isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)info[@"issued_at"]) == CFBooleanGetTypeID() ||
        [info[@"issued_at"] doubleValue] <= 0 ||
        [info[@"issued_at"] doubleValue] != [info[@"issued_at"] longLongValue]) {
        if (error) *error = DORHSupporterLicenseError(23, @"Unsupported binding certificate payload");
        return nil;
    }
    return info;
}

static inline BOOL DORHSupporterProveBoundDeviceKey(NSString *expectedFingerprint, NSString *certificate)
{
    // Reading a public fingerprint is insufficient: prove possession using a fresh nonce.
    SecKeyRef privateKey = DORHSupporterCopyExistingDevicePrivateKey();
    if (!privateKey) return NO;
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    NSData *point = publicKey ? DORHSupporterCopyDevicePublicKeyData(publicKey, NULL, NULL) : nil;
    BOOL valid = point && [DORHSupporterDeviceKeyFingerprint(point)[@"key_fingerprint"] isEqualToString:expectedFingerprint];
    unsigned char nonce[32];
    valid = valid && SecRandomCopyBytes(kSecRandomDefault, sizeof(nonce), nonce) == errSecSuccess;
    if (valid) {
        NSMutableData *message = [[@"DopamineRH-RHB1-Possession-v1" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
        [message appendBytes:nonce length:sizeof(nonce)];
        [message appendData:[certificate dataUsingEncoding:NSUTF8StringEncoding]];
        NSData *signature = DORHSupporterSignWithDeviceKey(privateKey, message, NULL);
        valid = signature && DORHSupporterVerifyDeviceKeySignature(publicKey, message, signature, NULL);
    }
    if (publicKey) CFRelease(publicKey);
    CFRelease(privateKey);
    return valid;
}

static inline NSDictionary *DORHSupporterVerifyBoundLicense(NSString *license, NSString *certificate, NSError **error)
{
    // Cache only in this process and by both signed wires. Removal is checked by the caller.
    @synchronized (NSUserDefaults.class) {
        static NSString *cachedLicense = nil;
        static NSString *cachedCertificate = nil;
        static NSDictionary *cachedInfo = nil;
        if ([cachedLicense isEqualToString:license] && [cachedCertificate isEqualToString:certificate])
            return cachedInfo;
        NSDictionary *binding = DORHSupporterBindingCertificateInfo(certificate, error);
        if (!binding) return nil;
        NSString *digest = DORHSupporterSHA256([license dataUsingEncoding:NSUTF8StringEncoding]);
        if (![binding[@"license_sha256"] isEqualToString:digest]) {
            if (error) *error = DORHSupporterLicenseError(24, @"Binding certificate is for another license");
            return nil;
        }
        NSDictionary *info = DORHSupporterVerifyLicenseCodeForDevice(license, binding[@"device"], error);
        if (!info || ![info[@"sid"] isEqualToString:binding[@"sid"]]) return nil;
        NSDictionary *hardware = DORHSupporterHardwareIdentityProbe();
        if (![hardware[@"available"] boolValue] ||
            ![hardware[@"algorithm"] isEqualToString:binding[@"hardware_protocol"]] ||
            ![hardware[@"hardware_hash"] isEqualToString:binding[@"hardware_hash"]] ||
            !DORHSupporterProveBoundDeviceKey(binding[@"key_fingerprint"], certificate)) {
            if (error) *error = DORHSupporterLicenseError(25, @"Binding does not match this device or its existing device key");
            return nil;
        }
        NSMutableDictionary *boundInfo = [info mutableCopy];
        boundInfo[@"binding_status"] = @"bound";
        cachedInfo = [boundInfo copy];
        cachedLicense = [license copy];
        cachedCertificate = [certificate copy];
        return cachedInfo;
    }
}

static inline BOOL DORHSupporterBindingIsRequired(void)
{
    NSDictionary *state = DORHSupporterReadPersistentState();
    id required = state[DORHSupporterBindingRequiredKey];
    return DORH_SUPPORTER_REQUIRE_BINDING || state[DORHSupporterBindingCertificateKey] != nil ||
        (required != nil && (![required respondsToSelector:@selector(boolValue)] || [required boolValue]));
}
