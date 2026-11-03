XCODE_PROJECT = src/idownloadd.xcodeproj
XCODE_SCHEME = idownloadd
CS_FLAGS = CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
CONFIGURATION = Release

OUTPUT_NAME = idownloadd
SWIFT_PACKAGE_DIR = $(CURDIR)/.swiftpm
SWIFT_PACKAGE_FLAGS = -clonedSourcePackagesDirPath "$(SWIFT_PACKAGE_DIR)"

build:
	xcodebuild -resolvePackageDependencies -project $(XCODE_PROJECT) -scheme $(XCODE_SCHEME) $(SWIFT_PACKAGE_FLAGS)
	xcodebuild -disableAutomaticPackageResolution -clonedSourcePackagesDirPath "$(SWIFT_PACKAGE_DIR)" -archivePath ./.build -project $(XCODE_PROJECT) -scheme $(XCODE_SCHEME) -configuration $(CONFIGURATION) -destination generic/platform=iOS archive $(CS_FLAGS)
	@cp -f ./.build.xcarchive/Products/usr/local/bin/$(OUTPUT_NAME) .
	@rm -rf ./.build.xcarchive
	@ldid -Cadhoc -Sentitlements.plist $(OUTPUT_NAME)

clean:
	xcodebuild -clonedSourcePackagesDirPath "$(SWIFT_PACKAGE_DIR)" -project $(XCODE_PROJECT) -scheme $(XCODE_SCHEME) -configuration $(CONFIGURATION) -destination generic/platform=iOS clean
	@rm -rf $(OUTPUT_NAME)

default: build
