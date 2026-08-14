#!/usr/bin/env ruby
# frozen_string_literal: true

require 'xcodeproj'

root = File.expand_path('..', __dir__)
project_path = File.join(root, 'WinterVoice.xcodeproj')
project = Xcodeproj::Project.new(project_path)
project.root_object.attributes['LastSwiftUpdateCheck'] = '2650'
project.root_object.attributes['LastUpgradeCheck'] = '2650'

app = project.new_target(:application, 'WinterVoice', :osx, '14.0')
tests = project.new_target(:unit_test_bundle, 'WinterVoiceTests', :osx, '14.0')

# Pinned upstream whisper.cpp XCFramework wrapped as a local Swift package.
whisper_package = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
whisper_package.relative_path = 'Vendor/WhisperBinary'
project.root_object.package_references << whisper_package
whisper_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
whisper_product.package = whisper_package
whisper_product.product_name = 'WhisperBinary'
app.package_product_dependencies << whisper_product
whisper_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
whisper_build_file.product_ref = whisper_product
app.frameworks_build_phase.files << whisper_build_file

app_group = project.main_group.new_group('WinterVoice', 'WinterVoice')
Dir.glob(File.join(root, 'WinterVoice', '**', '*.swift')).sort.each do |path|
  app.add_file_references([app_group.new_file(path.delete_prefix(File.join(root, 'WinterVoice') + '/'))])
end

resources = app_group.new_group('Resources', 'Resources')
resources.new_file('Info.plist')
asset_catalog = resources.new_file('Assets.xcassets')
# Bundled UI typeface (Inter); registered via ATSApplicationFontsPath = Fonts.
fonts_folder = resources.new_file('Fonts')
fonts_folder.last_known_file_type = 'folder'
# Recording chimes; copied as a folder reference so they land in
# Contents/Resources/Sounds and load via url(forResource:subdirectory:).
sounds_folder = resources.new_file('Sounds')
sounds_folder.last_known_file_type = 'folder'
app.add_resources([asset_catalog, fonts_folder, sounds_folder])

test_group = project.main_group.new_group('WinterVoiceTests', 'WinterVoiceTests')
Dir.glob(File.join(root, 'WinterVoiceTests', '**', '*.swift')).sort.each do |path|
  tests.add_file_references([test_group.new_file(path.delete_prefix(File.join(root, 'WinterVoiceTests') + '/'))])
end

app.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.winterzxzz.WinterVoice'
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['INFOPLIST_FILE'] = 'WinterVoice/Resources/Info.plist'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['SWIFT_STRICT_CONCURRENCY'] = 'complete'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  # Hardened Runtime blocks DYLD_INSERT_LIBRARIES-style injection into a
  # process holding Microphone, Accessibility, and Input Monitoring grants.
  config.build_settings['ENABLE_HARDENED_RUNTIME'] = 'YES'
  config.build_settings.delete('DEVELOPMENT_TEAM')
  config.build_settings.delete('CODE_SIGN_ENTITLEMENTS')
end

tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.winterzxzz.WinterVoiceTests'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/WinterVoice.app/Contents/MacOS/WinterVoice'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
end

# Normalize the targets and project root before xcodeproj records their UUIDs as
# scalar strings inside PBXContainerItemProxy. A final pass then covers the
# dependency objects themselves.
project.sort
project.predictabilize_uuids
tests.add_dependency(app)
project.sort
project.predictabilize_uuids
# Keep local signing selectable in Xcode. The owner chooses a Personal Team
# locally; this generated project must not persist a particular team or
# entitlement file.
project.root_object.attributes.delete('TargetAttributes')
project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(tests)
scheme.set_launch_target(app)
scheme.add_test_target(tests)
scheme.save_as(project_path, 'WinterVoice', true)
