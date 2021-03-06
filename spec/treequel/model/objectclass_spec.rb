#!/usr/bin/env ruby

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.parent.parent.parent

	libdir = basedir + "lib"

	$LOAD_PATH.unshift( basedir ) unless $LOAD_PATH.include?( basedir )
	$LOAD_PATH.unshift( libdir ) unless $LOAD_PATH.include?( libdir )
}

require 'rspec'

require 'spec/lib/helpers'

require 'treequel/model'
require 'treequel/model/objectclass'
require 'treequel/branchset'



#####################################################################
###	C O N T E X T S
#####################################################################

describe Treequel::Model::ObjectClass do

	before( :all ) do
		setup_logging( :fatal )
	end

	before( :each ) do
		@conn = mock( "ldap connection object" )
		@directory = get_fixtured_directory( @conn )
		Treequel::Model.directory = @directory
	end

	after( :each ) do
		Treequel::Model.directory = nil
		Treequel::Model.objectclass_registry.clear
		Treequel::Model.base_registry.clear
	end

	after( :all ) do
		reset_logging()
	end


	it "outputs a warning when it is included instead of used to extend a Module" do
		Treequel::Model::ObjectClass.should_receive( :warn ).
			with( /extending.*rather than appending/i )
		mixin = Module.new do
			include Treequel::Model::ObjectClass
		end
	end


	context "extended module" do

		it "can declare a required objectClass" do
			mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_objectclasses :inetOrgPerson
			end

			mixin.model_objectclasses.should == [:inetOrgPerson]
		end

		it "can declare a required objectClass as a String" do
			mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_objectclasses 'apple-computer-list'
			end

			mixin.model_objectclasses.should == [:'apple-computer-list']
		end

		it "can declare multiple required objectClasses" do
			mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_objectclasses :inetOrgPerson, :acmeAccount
			end

			mixin.model_objectclasses.should == [ :inetOrgPerson, :acmeAccount ]
		end

		it "can declare a single base" do
			mixin = Module.new do
				extend Treequel::Model::ObjectClass,
				       Treequel::TestConstants
				model_objectclasses :device
				model_bases TEST_PHONES_DN
			end

			mixin.model_bases.should == [TEST_PHONES_DN]
		end

		it "can declare a base with spaces" do
			mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_objectclasses :device
				model_bases 'ou=phones, dc=acme, dc=com'
			end

			mixin.model_bases.should == ['ou=phones,dc=acme,dc=com']
		end

		it "can declare multiple bases" do
			mixin = Module.new do
				extend Treequel::Model::ObjectClass,
				       Treequel::TestConstants
				model_objectclasses :ipHost
				model_bases TEST_HOSTS_DN,
				            TEST_SUBHOSTS_DN
			end

			mixin.model_bases.should include( TEST_HOSTS_DN, TEST_SUBHOSTS_DN )
		end

		it "raises an exception when creating a search for a mixin that hasn't declared " +
		     "at least one objectClass or base"  do
			mixin = Module.new do
				extend Treequel::Model::ObjectClass
			end

			expect {
				mixin.search( @directory )
			}.to raise_exception( Treequel::ModelError, /has no search criteria defined/ )
		end

		it "defaults to using Treequel::Model as its model class" do
			mixin = Module.new do
				extend Treequel::Model::ObjectClass
			end

			mixin.model_class.should == Treequel::Model
		end

		it "can declare a model class other than Treequel::Model" do
			class MyModel < Treequel::Model; end
			mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_class MyModel
			end

			mixin.model_class.should == MyModel
		end

		it "re-registers objectClasses that have already been declared when declaring a " +
		     "new model class" do
			class MyModel < Treequel::Model; end

			mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_objectclasses :inetOrgPerson
				model_class MyModel
			end

			Treequel::Model.objectclass_registry[:inetOrgPerson].should_not include( mixin )
			MyModel.objectclass_registry[:inetOrgPerson].should include( mixin )
		end

		it "re-registers bases that have already been declared when declaring a " +
		     "new model class" do
			class MyModel < Treequel::Model; end

			mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_bases 'ou=people,dc=acme,dc=com', 'ou=notpeople,dc=acme,dc=com'
				model_class MyModel
			end

			Treequel::Model.base_registry['ou=people,dc=acme,dc=com'].should_not include( mixin )
			MyModel.base_registry['ou=people,dc=acme,dc=com'].should include( mixin )
		end

		it "re-registers bases that have already been declared when declaring a " +
		     "new model class" do
			class MyModel < Treequel::Model; end

			mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_bases 'ou=people,dc=acme,dc=com', 'ou=notpeople,dc=acme,dc=com'
				model_class MyModel
			end

			Treequel::Model.base_registry['ou=people,dc=acme,dc=com'].should_not include( mixin )
			MyModel.base_registry['ou=people,dc=acme,dc=com'].should include( mixin )
		end

		it "uses the directory associated with its model_class instead of Treequel::Model's if " +
		   "its model_class is set when creating a search Branchset"  do
			conn = mock( "ldap connection object" )
			directory = get_fixtured_directory( conn )

			class MyModel < Treequel::Model; end
			MyModel.directory = directory

			mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_objectclasses :inetOrgPerson
				model_class MyModel
			end

			result = mixin.search

			result.should be_a( Treequel::Branchset )
			result.branch.directory.should == directory
		end

		it "delegates Branchset methods through the Branchset returned by its #search method" do
			mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_objectclasses :inetOrgPerson
			end

			mixin.filter( :mail ).should be_a( Treequel::Branchset )
		end

		it "delegates Branchset Enumerable methods through the Branchset returned by its " +
		   "#search method" do
			@conn.stub( :bound? ).and_return( true )
			@conn.should_receive( :search_ext2 ).
				with( TEST_BASE_DN, LDAP::LDAP_SCOPE_SUBTREE, "(objectClass=inetOrgPerson)",
			          [], false, [], [], 0, 0, 1, "", nil ).
				and_return([ TEST_PERSON_ENTRY ])

			mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_objectclasses :inetOrgPerson
			end

			result = mixin.first

			result.should be_a( Treequel::Model )
			result.should be_a( mixin )
			result.dn.should == TEST_PERSON_ENTRY['dn'].first
		end

	end

	context "model instantiation" do

		it "can instantiate a new model object with its declared objectClasses" do
			mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_objectclasses :inetOrgPerson
			end

			result = mixin.create( TEST_PERSON_DN )
			result.should be_a( Treequel::Model )
			result[:objectClass].should include( 'inetOrgPerson' )
			result[TEST_PERSON_DN_ATTR].should == [ TEST_PERSON_DN_VALUE ]
		end

		it "can instantiate a new model object with its declared objectClasses in a directory " +
		   "other than the one associated with its model_class" do
			mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_objectclasses :inetOrgPerson
			end

			result = mixin.create( @directory, TEST_PERSON_DN )
			result.should be_a( Treequel::Model )
			result[:objectClass].should include( 'inetOrgPerson' )
			result[TEST_PERSON_DN_ATTR].should == [ TEST_PERSON_DN_VALUE ]
		end

		it "doesn't add the extracted DN attribute if it's already present in the entry" do
			mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_objectclasses :inetOrgPerson
			end

			result = mixin.create( TEST_PERSON_DN,
				TEST_PERSON_DN_ATTR => [TEST_PERSON_DN_VALUE] )
			result.should be_a( Treequel::Model )
			result[:objectClass].should include( 'inetOrgPerson' )
			result[TEST_PERSON_DN_ATTR].should have( 1 ).member
			result[TEST_PERSON_DN_ATTR].should == [ TEST_PERSON_DN_VALUE ]
		end

		it "merges objectClasses passed to the creation method" do
			mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_objectclasses :inetOrgPerson
			end

			result = mixin.create( TEST_PERSON_DN,
				:objectClass => [:person, :inetOrgPerson] )
			result.should be_a( Treequel::Model )
			result[:objectClass].should have( 2 ).members
			result[:objectClass].should include( 'inetOrgPerson', 'person' )
			result[TEST_PERSON_DN_ATTR].should have( 1 ).member
			result[TEST_PERSON_DN_ATTR].should include( TEST_PERSON_DN_VALUE )
		end

		it "handles the creation of objects with multi-value DNs" do
			mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_objectclasses :ipHost, :ieee802Device, :device
			end

			result = mixin.create( TEST_HOST_MULTIVALUE_DN )
			result.should be_a( Treequel::Model )
			result[:objectClass].should have( 3 ).members
			result[:objectClass].should include( 'ipHost', 'ieee802Device', 'device' )
			result[TEST_HOST_MULTIVALUE_DN_ATTR1].should include( TEST_HOST_MULTIVALUE_DN_VALUE1 )
			result[TEST_HOST_MULTIVALUE_DN_ATTR2].should include( TEST_HOST_MULTIVALUE_DN_VALUE2 )
		end

	end

	context "module that has one required objectClass declared" do

		before( :each ) do
			@conn = mock( "ldap connection object" )
			@directory = get_fixtured_directory( @conn )
			Treequel::Model.directory = @directory

			@mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_objectclasses :inetOrgPerson
			end
		end

		after( :each ) do
			Treequel::Model.objectclass_registry.clear
		end


		it "is returned as one of the mixins for entries with only that objectClass" do
			Treequel::Model.mixins_for_objectclasses( :inetOrgPerson ).
				should include( @mixin )
		end

		it "is not returned in the list of mixins to apply to an entry without that objectClass" do
			Treequel::Model.mixins_for_objectclasses( :device ).
				should_not include( @mixin )
		end

		it "can create a Branchset that will search for applicable entries"  do
			result = @mixin.search

			result.should be_a( Treequel::Branchset )
			result.base_dn.should == TEST_BASE_DN
			result.filter.to_s.should == '(objectClass=inetOrgPerson)'
			result.branch.directory.should == @directory
		end

		it "can create a Branchset that will search for applicable entries in a Directory other " +
		   "than the one set for Treequel::Model"  do
			conn = mock( "second ldap connection object" )
			directory = get_fixtured_directory( conn )

			result = @mixin.search( directory )

			result.should be_a( Treequel::Branchset )
			result.base_dn.should == TEST_BASE_DN
			result.filter.to_s.should == '(objectClass=inetOrgPerson)'
			result.branch.directory.should == directory
		end

	end

	context "module that has more than one required objectClass declared" do

		before( :each ) do
			@mixin = Module.new do
				extend Treequel::Model::ObjectClass
				model_objectclasses :device, :ipHost
			end
		end

		after( :each ) do
			Treequel::Model.objectclass_registry.clear
		end


		it "is returned as one of the mixins to apply to entries with all of its required " +
		     "objectClasses" do
			Treequel::Model.mixins_for_objectclasses( :device, :ipHost ).
				should include( @mixin )
		end

		it "is not returned in the list of mixins to apply to an entry with only one of its " +
		     "objectClasses" do
			Treequel::Model.mixins_for_objectclasses( :device ).
				should_not include( @mixin )
		end

		it "can create a Branchset that will search for applicable entries"  do
			result = @mixin.search

			result.should be_a( Treequel::Branchset )
			result.base_dn.should == TEST_BASE_DN
			result.filter.to_s.should == '(&(objectClass=device)(objectClass=ipHost))'
			result.branch.directory.should == @directory
		end

		it "can create a Branchset that will search for applicable entries in a Directory other " +
		   "than the one set for Treequel::Model"  do
			conn = mock( "second ldap connection object" )
			directory = get_fixtured_directory( conn )

			result = @mixin.search( directory )

			result.should be_a( Treequel::Branchset )
			result.base_dn.should == TEST_BASE_DN
			result.filter.to_s.should == '(&(objectClass=device)(objectClass=ipHost))'
			result.branch.directory.should == directory
		end

	end

	context "module that has one base declared" do
		before( :each ) do
			@mixin = Module.new do
				extend Treequel::Model::ObjectClass,
				       Treequel::TestConstants
				model_bases TEST_PEOPLE_DN
			end
		end

		after( :each ) do
			Treequel::Model.base_registry.clear
		end


		it "is returned as one of the mixins to apply to an entry that is a child of its base" do
			Treequel::Model.mixins_for_dn( TEST_PERSON_DN ).
				should include( @mixin )
		end

		it "is not returned as one of the mixins to apply to an entry that is not a child of " +
		   "its base" do
			Treequel::Model.mixins_for_dn( TEST_ROOM_DN ).
				should_not include( @mixin )
		end

		it "can create a Branchset that will search for applicable entries"  do
			result = @mixin.search

			result.should be_a( Treequel::Branchset )
			result.base_dn.should == TEST_PEOPLE_DN
			result.filter.to_s.should == '(objectClass=*)'
			result.branch.directory.should == @directory
		end

		it "can create a Branchset that will search for applicable entries in a Directory other " +
		   "than the one set for Treequel::Model"  do
			conn = mock( "second ldap connection object" )
			directory = get_fixtured_directory( conn )

			result = @mixin.search( directory )

			result.should be_a( Treequel::Branchset )
			result.base_dn.should == TEST_PEOPLE_DN
			result.filter.to_s.should == '(objectClass=*)'
			result.branch.directory.should == directory
		end

	end

	context "module that has more than one base declared" do
		before( :each ) do
			@mixin = Module.new do
				extend Treequel::Model::ObjectClass,
				       Treequel::TestConstants
				model_bases TEST_HOSTS_DN,
				            TEST_SUBHOSTS_DN
			end
		end

		after( :each ) do
			Treequel::Model.base_registry.clear
		end


		it "is returned as one of the mixins to apply to an entry that is a child of one of " +
		   "its bases" do
			Treequel::Model.mixins_for_dn( TEST_SUBHOST_DN ).
				should include( @mixin )
		end

		it "is not returned as one of the mixins to apply to an entry that is not a child of " +
		   "its base" do
			Treequel::Model.mixins_for_dn( TEST_PERSON_DN ).
				should_not include( @mixin )
		end

		it "can create a BranchCollection that will search for applicable entries"  do
			result = @mixin.search

			result.should be_a( Treequel::BranchCollection )
			result.base_dns.should have( 2 ).members
			result.base_dns.should include( TEST_HOSTS_DN, TEST_SUBHOSTS_DN )
			result.branchsets.each do |brset|
				brset.filter_string.should == '(objectClass=*)'
				brset.branch.directory.should == @directory
			end
		end

		it "can create a BranchCollection that will search for applicable entries in a Directory " +
		   " other than the one set for Treequel::Model"  do
			conn = mock( "second ldap connection object" )
			directory = get_fixtured_directory( conn )

			result = @mixin.search( directory )

			result.should be_a( Treequel::BranchCollection )
			result.base_dns.should have( 2 ).members
			result.base_dns.should include( TEST_HOSTS_DN, TEST_SUBHOSTS_DN )
			result.branchsets.each do |brset|
				brset.filter_string.should == '(objectClass=*)'
				brset.branch.directory.should == directory
			end
		end

	end

end


# vim: set nosta noet ts=4 sw=4:
