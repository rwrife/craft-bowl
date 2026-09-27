.PHONY: bootstrap project open build lint issues

bootstrap:            ## install tooling (macOS)
	brew list xcodegen >/dev/null 2>&1 || brew install xcodegen
	brew list swift-format >/dev/null 2>&1 || brew install swift-format

project:              ## generate CraftBowl.xcodeproj from project.yml
	xcodegen generate

open: project
	open CraftBowl.xcodeproj

build: project        ## build the iOS app for the simulator
	xcodebuild -project CraftBowl.xcodeproj -scheme CraftBowl \
	  -destination 'generic/platform=iOS Simulator' build

lint:
	swift-format lint --recursive --strict App Packages

issues:               ## create GitHub labels/milestones/issues (needs `gh auth login`)
	python3 scripts/create_issues.py
