#!/usr/bin/env ruby

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.parent.parent

	libdir = basedir + "lib"

	$LOAD_PATH.unshift( libdir ) unless $LOAD_PATH.include?( libdir )
}

require 'spec'
require 'spec/lib/constants'
require 'spec/lib/helpers'

require 'treequel/branchset'
require 'treequel/branchcollection'
require 'treequel/control'

include Treequel::TestConstants
include Treequel::Constants

#####################################################################
###	C O N T E X T S
#####################################################################

describe Treequel::Branchset do
	include Treequel::SpecHelpers

	# Make the specs read more clearly
	class << self
		alias_method :they, :it
	end

	DEFAULT_PARAMS = {
		:limit           => 0,
		:selectattrs     => [],
		:timeout         => 0,
		:client_controls => [],
		:server_controls => [],
	}

	before( :all ) do
		setup_logging( :fatal )
	end

	after( :all ) do
		reset_logging()
	end

	before( :each ) do
		@directory = mock( "treequel directory ", :registered_controls => [] )
		@branch = mock( "treequel branch", :dn => 'thedn' )
		@branch.stub!( :directory ).and_return( @directory )
		@params = DEFAULT_PARAMS.dup
	end


	describe "instances" do
		before( :each ) do
			@branchset = Treequel::Branchset.new( @branch )
		end

		they "are Enumerable" do
			resultbranch = mock( "Result Branch" )

			@branch.should_receive( :search ).
				with( Treequel::Branchset::DEFAULT_SCOPE, @branchset.filter, @params ).
				and_yield( resultbranch )
			resultbranch.should_receive( :dn ).and_return( :its_dn )

			@branchset.all? {|b| b.dn }
		end

		# 
		# #empty?
		# 
		they "know that they are empty if they don't match at least one entry" do
			params = @params.merge( :limit => 1 )
			@branch.should_receive( :search ).
				with( Treequel::Branchset::DEFAULT_SCOPE, @branchset.filter, params ).
				and_return( [] )

			@branchset.should be_empty()
		end

		they "know that they are empty if they match at least one entry" do
			params = @params.merge( :limit => 1 )
			@branch.should_receive( :search ).
				with( Treequel::Branchset::DEFAULT_SCOPE, @branchset.filter, params ).
				and_return( [:a_branch] )

			@branchset.should_not be_empty()
		end

		# 
		# #map
		# 
		they "can be mapped into an Array of attribute values" do
			resultbranch = mock( "Result Branch" )
			resultbranch2 = mock( "Result Branch 2" )

			@branch.should_receive( :search ).
				with( Treequel::Branchset::DEFAULT_SCOPE, @branchset.filter, @params ).
				and_yield( resultbranch ).and_yield( resultbranch2 )
			resultbranch.should_receive( :[] ).with( :cn ).and_return([ :first_cn ])
			resultbranch2.should_receive( :[] ).with( :cn ).and_return([ :second_cn ])

			@branchset.map( :cn ).should == [[:first_cn], [:second_cn]]
		end


		# 
		# #to_hash
		# 
		they "can be mapped into a Hash of entries keyed by one of their attributes" do
			resultbranch = mock( "Result Branch" )
			resultbranch2 = mock( "Result Branch 2" )

			@branch.should_receive( :search ).
				with( Treequel::Branchset::DEFAULT_SCOPE, @branchset.filter, @params ).
				and_yield( resultbranch ).and_yield( resultbranch2 )

			resultbranch.should_receive( :[] ).with( :email ).
				and_return([ :first_email ])
			resultbranch.should_receive( :entry ).and_return( :entry1 )
			resultbranch2.should_receive( :[] ).with( :email ).
				and_return([ :second_email, :second_second_email ])
			resultbranch2.should_receive( :entry ).and_return( :entry2 )

			@branchset.to_hash( :email ).should == {
				:first_email => :entry1,
				:second_email => :entry2,
			}
		end


		they "can be mapped into a Hash of tuples using two attributes" do
			resultbranch = mock( "Result Branch" )
			resultbranch2 = mock( "Result Branch 2" )

			@branch.should_receive( :search ).
				with( Treequel::Branchset::DEFAULT_SCOPE, @branchset.filter, @params ).
				and_yield( resultbranch ).and_yield( resultbranch2 )

			resultbranch.should_receive( :[] ).with( :email ).
				and_return([ :first_email ])
			resultbranch.should_receive( :[] ).with( :cn ).
				and_return([ :first_cn ])
			resultbranch2.should_receive( :[] ).with( :email ).
				and_return([ :second_email, :second_second_email ])
			resultbranch2.should_receive( :[] ).with( :cn ).
				and_return([ :second_cn, :second_second_cn ])

			@branchset.to_hash( :email, :cn ).should == {
				:first_email => :first_cn,
				:second_email => :second_cn,
			}
		end

		#
		# #+
		#
		they "can be combined into a BranchCollection by adding them together" do
			other_branch = mock( "second treequel branch", :dn => 'theotherdn' )
			other_branch.stub!( :directory ).and_return( @directory )
			other_branchset = Treequel::Branchset.new( other_branch )

			result = @branchset + other_branchset
			result.should be_a( Treequel::BranchCollection )
			result.branchsets.should have( 2 ).members
			result.branchsets.should include( @branchset, other_branchset )
		end

		they "can be combined with a Branch into a BranchCollection by adding it" do
			other_branch = mock( "second treequel branch", :dn => 'theotherdn' )
			other_branch.stub!( :directory ).and_return( @directory )

			result = @branchset + other_branch
			result.should be_a( Treequel::BranchCollection )
			result.branchsets.should have( 2 ).members
			result.branchsets.should include( @branchset )
			result.branchsets.select {|bs| bs != @branchset }.
				first.branch.should == other_branch
		end

	end

	describe "instance with no filter, options, or scope set" do

		before( :each ) do
			@branchset = Treequel::Branchset.new( @branch )
		end

		it "can clone itself with merged options" do
			newset = @branchset.clone( :scope => :one )
			newset.should be_a( Treequel::Branchset )
			newset.should_not equal( @branchset )
			newset.options.should_not equal( @branchset.options )
			newset.scope.should == :one
		end


		# 
		# #filter
		# 

		it "generates a valid filter string" do
			@branchset.filter_string.should == '(objectClass=*)'
		end


		it "performs a search using the default filter and scope when all records are requested" do
			@branch.should_receive( :search ).
				with( Treequel::Branchset::DEFAULT_SCOPE, @branchset.filter, @params ).
				and_yield( :matching_branches )

			@branchset.all.should == [ :matching_branches ]
		end

		it "performs a search using the default filter, scope, and a limit of 1 when the first " +
		   "record is requested" do
			params = @params.merge( :limit => 1 )
			@branch.should_receive( :search ).
				with( Treequel::Branchset::DEFAULT_SCOPE, @branchset.filter, params ).
				and_return( [:first_matching_branch, :other_branches] )

			@branchset.first.should == :first_matching_branch
		end

		it "creates a new branchset cloned from itself with the specified filter" do
			newset = @branchset.filter( :clothing, 'pants' )
			newset.filter_string.should == '(clothing=pants)'
		end

		# 
		# #scope
		# 

		it "provides a reader for its scope" do
			@branchset.scope.should == :subtree
		end

		it "can return the DN of its base" do
			@branch.should_receive( :dn ).and_return( :foo )
			@branchset.base_dn.should == :foo
		end

		it "can create a new branchset cloned from itself with a different scope" do
			newset = @branchset.scope( :onelevel )
			newset.should be_a( Treequel::Branchset )
			newset.should_not equal( @branchset )
			newset.options.should_not equal( @branchset.options )
			newset.scope.should == :onelevel
		end

		it "can create a new branchset cloned from itself with a different string scope" do
			newset = @branchset.scope( 'sub' )
			newset.scope.should == :sub
		end

		it "uses its scope setting as the scope to use when searching" do
			@branchset.options[:scope] = :onelevel
			@branch.should_receive( :search ).
				with( :onelevel, @branchset.filter, @params ).
				and_yield( :matching_branches )

			@branchset.all.should == [:matching_branches]
		end

		# 
		# #select
		# 
		it "can create a new branchset cloned from itself with an attribute selection" do
			newset = @branchset.select( :l, :lastName, :disabled )
			newset.select.should == [ 'l', 'lastName', 'disabled' ]
		end

		it "can create a new branchset cloned from itself with all attributes selected" do
			newset = @branchset.select_all
			newset.select.should == []
		end

		it "can create a new branchset cloned from itself with additional attributes selected" do
			@branchset.options[:select] = [ :l, :cn, :uid ]
			newset = @branchset.select_more( :firstName, :uid, :lastName )
			newset.select.should == [ 'l', 'cn', 'uid', 'firstName', 'lastName' ]
		end

		it "adding attributes via #select_more should work even if there was no current " +
		   "attribute selection" do
			newset = @branchset.select_more( :firstName, :uid, :lastName, :objectClass )
			newset.select.should include( 'uid', 'firstName', 'lastName', 'objectClass' )
		end

		it "uses its selection as the list of attributes to fetch when searching" do
			@branchset.options[:select] = [ :l, :cn, :uid ]
			@branch.should_receive( :search ).
				with( Treequel::Branchset::DEFAULT_SCOPE, @branchset.filter,
				      @params.merge(:selectattrs => ['l', 'cn', 'uid']) ).
				and_yield( :matching_branches )

			@branchset.all.should == [:matching_branches]
		end

		# 
		# #timeout
		# 

		it "can create a new branchset cloned from itself with a timeout" do
			newset = @branchset.timeout( 30 )
			newset.timeout.should == 30.0
		end

		it "can create a new branchset cloned from itself without a timeout" do
			@branchset.options[:timeout] = 5.375
			newset = @branchset.without_timeout
			newset.timeout.should == 0
		end

		it "uses its timeout as the timeout values when searching" do
			@branchset.options[:timeout] = 5.375
			@branch.should_receive( :search ).
				with( Treequel::Branchset::DEFAULT_SCOPE, @branchset.filter,
				      @params.merge(:timeout => 5.375) ).
				and_yield( :matching_branches )

			@branchset.all.should == [:matching_branches]
		end

		# 
		# #order
		# 

		# it "can create a new branchset cloned from itself with a sort-order attribute" do
		# 	newset = @branchset.order( :uid )
		# 	newset.order.should == :uid
		# end
		# 
		# it "converts a string sort-order attribute to a Symbol" do
		# 	newset = @branchset.order( 'uid' )
		# 	newset.order.should == :uid
		# end
		# 
		# it "can set a sorting function instead of an attribute" do
		# 	newset = @branchset.order {|branch| branch.uid }
		# 	newset.order.should be_a( Proc )
		# end
		# 
		# it "can create a new branchset cloned from itself without a sort-order attribute" do
		# 	@branchset.options[:order] = :uid
		# 	newset = @branchset.order( nil )
		# 	newset.order.should == nil
		# end
		# 
		# it "uses its order attribute list when searching" do
		# 	@branchset.options[:order] = [ :uid ]
		# 	@branch.should_receive( :directory ).and_return( @directory )
		# 	@directory.should_receive( :search ).
		# 		with( @branch, Treequel::Branchset::DEFAULT_SCOPE, @branchset.filter,
		# 		      @params.merge(:sortby => ['uid']) ).
		# 		and_yield( :matching_branches )
		# 
		# 	@branchset.all.should == [:matching_branches]
		# end

		# 
		# #limit
		# 
		it "can create a new branchset cloned from itself with a limit attribute" do
			newset = @branchset.limit( 5 )
			newset.limit.should == 5
		end

		it "can create a new branchset cloned from itself without a limit" do
			newset = @branchset.without_limit
			newset.limit.should == 0
		end

		it "uses its limit as the limit when searching" do
			@branchset.options[:limit] = 8
			@branch.should_receive( :search ).
				with( Treequel::Branchset::DEFAULT_SCOPE, @branchset.filter,
				      @params.merge(:limit => 8) ).
				and_yield( :matching_branches )

			@branchset.all.should == [:matching_branches]
		end

		# 
		# #as
		# 
		it "can create a new branchset cloned from itself that will return instances of a different branch class" do
			subclass = Class.new( Treequel::Branch )
			@branch.stub!( :directory ).and_return( :the_directory )
			@branch.stub!( :dn ).and_return( TEST_HOSTS_DN )
			newset = @branchset.as( subclass )
			newset.branch.should be_an_instance_of( subclass )
		end

	end

	describe "instance with no filter, and scope set to 'onelevel'" do

		before( :each ) do
			@branchset = Treequel::Branchset.new( @branch, :scope => :onelevel )
		end


		it "generates a valid filter string" do
			@branchset.filter_string.should == '(objectClass=*)'
		end

		it "performs a search using the default filter and scope when all records are requested" do
			@branch.should_receive( :search ).
				with( :onelevel, @branchset.filter, @params ).
				and_yield( :matching_branches )

			@branchset.all.should == [:matching_branches]
		end

	end

	describe "created for a directory with registered controls" do

		before( :all ) do
			@control = Module.new {
				include Treequel::Control
				OID = '3.1.4.1.5.926'

				def yep; end
				def get_client_controls; [:client_control]; end
				def get_server_controls; [:server_control]; end
			}
		end

		before( :each ) do
			@directory.stub!( :registered_controls ).and_return([ @control ])
		end

		it "extends instances of itself with any controls registered with its Branch's Directory" do
			set = Treequel::Branchset.new( @branch )
			set.should respond_to( :yep )
		end

		it "appends client controls to search arguments" do
			resultbranch = mock( "Result Branch" )
			set = Treequel::Branchset.new( @branch )

			@params[:server_controls] = [:server_control]
			@params[:client_controls] = [:client_control]

			@branch.should_receive( :search ).
				with( Treequel::Branchset::DEFAULT_SCOPE, set.filter, @params ).
				and_yield( resultbranch )

			set.all.should == [ resultbranch ]
		end

	end

end


# vim: set nosta noet ts=4 sw=4:
