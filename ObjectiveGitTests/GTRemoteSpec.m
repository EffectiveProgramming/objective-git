//
//  GTRemoteSpec.m
//  ObjectiveGitFramework
//
//  Created by Alan Rogers on 16/10/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "GTRemote.h"

SpecBegin(GTRemote)

__block GTRemote *remote = nil;
__block GTRepository *repository = nil;
NSString *fetchRefspec = @"+refs/heads/*:refs/remotes/origin/*";

beforeEach(^{
	repository = self.testAppFixtureRepository;
	expect(repository).notTo.beNil();

	NSError *error = nil;
	GTConfiguration *configuration = [repository configurationWithError:&error];
	expect(configuration).toNot.beNil();
	expect(error).to.beNil();

	expect(configuration.remotes.count).to.beGreaterThanOrEqualTo(1);

	remote = configuration.remotes[0];
	expect(remote.name).to.equal(@"origin");
});

describe(@"properties", ^{
	it(@"should have values", ^{
		expect(remote.git_remote).toNot.beNil();
		expect(remote.name).to.equal(@"origin");
		expect(remote.URLString).to.equal(@"git@github.com:github/Test_App.git");

		expect(remote.fetchRefspecs).to.equal(@[ fetchRefspec ]);
	});
});

describe(@"updating", ^{
	it(@"URL string", ^{
		expect(remote.URLString).to.equal(@"git@github.com:github/Test_App.git");

		NSString *newURLString = @"https://github.com/github/Test_App.git";

		__block NSError *error = nil;
		expect([remote updateURLString:newURLString error:&error]).to.beTruthy();
		expect(error).to.beNil();

		expect(remote.URLString).to.equal(newURLString);
	});

	it(@"fetch refspecs", ^{
		expect(remote.fetchRefspecs).to.equal(@[ fetchRefspec ]);

		__block NSError *error = nil;
		expect([remote removeFetchRefspec:fetchRefspec error:&error]).to.beTruthy();
		expect(error).to.beNil();

		expect(remote.fetchRefspecs.count).to.equal(0);

		NSString *newFetchRefspec = @"+refs/heads/master:refs/remotes/origin/master";
		expect([remote addFetchRefspec:newFetchRefspec error:&error]).to.beTruthy();
		expect(error).to.beNil();

		expect(remote.fetchRefspecs).to.equal(@[ newFetchRefspec ]);
	});
});

describe(@"fetching", ^{
	__block NSURL *repositoryURL;
	__block NSURL *fetchingRepoURL;
	__block GTRepository *fetchingRepo;
	__block NSArray *remoteNames;
	__block NSString *remoteName;

	beforeEach(^{
		repositoryURL = repository.gitDirectoryURL;
		NSURL *fixturesURL = repositoryURL.URLByDeletingLastPathComponent;
		fetchingRepoURL = [fixturesURL URLByAppendingPathComponent:@"fetchrepo"];

		// Make sure there's no leftover
		[NSFileManager.defaultManager removeItemAtURL:fetchingRepoURL error:nil];

		NSError *error = nil;
		fetchingRepo = [GTRepository cloneFromURL:repositoryURL toWorkingDirectory:fetchingRepoURL options:nil error:&error transferProgressBlock:nil checkoutProgressBlock:nil];
		expect(fetchingRepo).notTo.beNil();
		expect(error).to.beNil();

		remoteNames = [fetchingRepo remoteNamesWithError:&error];
		expect(error).to.beNil();
		expect(remoteNames.count).to.beGreaterThanOrEqualTo(1);

		remoteName = remoteNames[0];
	});

	afterEach(^{
		[NSFileManager.defaultManager removeItemAtURL:fetchingRepoURL error:NULL];
	});

	describe(@"-remoteWithName:inRepository:error", ^{
		it(@"should return existing remotes", ^{
			NSError *error = nil;

			GTRemote *originRemote = [GTRemote remoteWithName:remoteName inRepository:fetchingRepo error:&error];
			expect(error).to.beNil();
			expect(originRemote).notTo.beNil();
		});

		it(@"should fail for non-existent remotes", ^{
			NSError *error = nil;

			GTRemote *originRemote = [GTRemote remoteWithName:@"blork" inRepository:fetchingRepo error:&error];
			expect(error).notTo.beNil();
			expect(originRemote).to.beNil();
		});
	});

	describe(@"-createRemoteWithName:url:inRepository:error", ^{
		it(@"should allow creating new remotes", ^{
			NSError *error = nil;
			GTRemote *remote = [GTRemote createRemoteWithName:@"newremote" url:@"git://user@example.com/testrepo.git" inRepository:fetchingRepo	error:&error];
			expect(error).to.beNil();
			expect(remote).notTo.beNil();

			GTRemote *newRemote = [GTRemote remoteWithName:@"newremote" inRepository:fetchingRepo error:&error];
			expect(error).to.beNil();
			expect(newRemote).notTo.beNil();
		});
	});

	describe(@"-fetchWithError:credentials:progress:", ^{
		it(@"allows remotes to be fetched", ^{
			NSError *error = nil;
			GTRemote *remote = [GTRemote remoteWithName:remoteName inRepository:fetchingRepo error:nil]; // Tested above

			BOOL result = [remote fetchWithError:&error credentialProvider:nil progress:nil];
			expect(error).to.beNil();
			expect(result).to.beTruthy();
		});

		it(@"brings in new commits", ^{
			NSError *error = nil;

			// Create a new commit in the master repo
			NSString *testData = @"Test";
			NSString *fileName = @"test.txt";
			BOOL res;
			GTTreeBuilder *treeBuilder = [[GTTreeBuilder alloc] initWithTree:nil error:nil];
			[treeBuilder addEntryWithData:[testData dataUsingEncoding:NSUTF8StringEncoding] fileName:fileName fileMode:GTFileModeBlob error:nil];

			GTTree *testTree = [treeBuilder writeTreeToRepository:repository error:nil];

			// We need the parent commit to make the new one
			GTBranch *currentBranch = [repository currentBranchWithError:nil];
			GTReference *currentReference = [currentBranch reference];

			GTEnumerator *commitEnum = [[GTEnumerator alloc] initWithRepository:repository error:nil];
			[commitEnum pushSHA:[currentReference targetSHA] error:nil];
			GTCommit *parent = [commitEnum nextObject];

			GTCommit *testCommit = [repository createCommitWithTree:testTree message:@"Test commit" parents:@[parent] updatingReferenceNamed:currentReference.name error:nil];
			expect(testCommit).notTo.beNil();

			// Now issue a fetch from the fetching repo
			GTRemote *remote = [GTRemote remoteWithName:remoteName inRepository:fetchingRepo error:nil];

			__block unsigned int receivedObjects = 0;
			res = [remote fetchWithError:&error credentialProvider:nil progress:^(const git_transfer_progress *stats, BOOL *stop) {
				receivedObjects += stats->received_objects;
				NSLog(@"%d", receivedObjects);
			}];
			expect(error).to.beNil();
			expect(res).to.beTruthy();
			expect(receivedObjects).to.equal(6);

			GTCommit *fetchedCommit = [fetchingRepo lookupObjectByOID:testCommit.OID objectType:GTObjectTypeCommit error:&error];
			expect(error).to.beNil();
			expect(fetchedCommit).notTo.beNil();

			GTTreeEntry *entry = [[fetchedCommit tree] entryWithName:fileName];
			expect(entry).notTo.beNil();

			GTBlob *fileData = (GTBlob *)[entry toObjectAndReturnError:&error];
			expect(error).to.beNil();
			expect(fileData).notTo.beNil();
			expect(fileData.content).to.equal(testData);
		});
	});
});

SpecEnd
