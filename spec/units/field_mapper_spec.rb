require 'spec_helper'

describe Solrizer::FieldMapper do
  
  # --- Test Mappings ----
  class TestMapper0 < Solrizer::FieldMapper
    id_field 'ident'
    module Descriptors0
      # Produces a _s suffix (overrides _tim)
      def self.unstemmed_searchable
        @unstemmed_searchable ||= UnstemmedDescriptor.new()
      end

      # Produces a _s suffix (overrides _tim)
      def self.searchable
        @searchable ||= SearchableDescriptor.new()
      end

      def self.edible
        @edible ||= EdibleDescriptor.new()
      end

      def self.fungible
        @fungible ||= FungibleDescriptor.new()
      end

      def self.laughable
        @laughable ||= LaughableDescriptor.new()
      end

      class UnstemmedDescriptor < Solrizer::Descriptor
        def name_and_converter(field_name, field_type)
          [field_name + '_s', lambda { |value| field_type == :date ? "#{value} o'clock" : value }]
        end
      end

      class SearchableDescriptor < Solrizer::Descriptor
        def name_and_converter(field_name, field_type)
          [field_name + '_s']
        end
      end

      class EdibleDescriptor < Solrizer::Descriptor
        def name_and_converter(field_name, field_type)
          [field_name + '_food']
        end
      end

      class FungibleDescriptor < Solrizer::Descriptor
        def name_and_converter(field_name, field_type)
          [field_name + fungible_type(field_type)]
        end
        def fungible_type(type)
          case type
          when :integer
            '_f1'
          when :date
            '_f0'
          else
            '_f2'
          end
        end
      end

      class LaughableDescriptor < Solrizer::Descriptor
        def name_and_converter(field_name, field_type)
          [field_name + laughable_type(field_type), laughable_converter(field_type)]
        end

        def laughable_type(type)
          case type
          when :integer
            '_ihaha'
          else
            '_haha'
          end
        end

        def laughable_converter(type)
          case type
          when :integer
            lambda do |value, field_name| 
              "How many #{field_name}s does it take to screw in a light bulb? #{value.capitalize}."
            end
          else
            lambda do |value| 
              "Knock knock. Who's there? #{value.capitalize}. #{value.capitalize} who?"
            end
          end
        end
      end
    end

    self.descriptors = [Descriptors0, Solrizer::DefaultDescriptors]
  end
  
  class TestMapper1 < TestMapper0
    module Descriptors1
      def self.fungible
        @fungible ||= FungibleDescriptor.new()
      end

      def self.simple
        @simple ||= SimpleDescriptor.new(lambda {|field_type| [field_type, :indexed]})
      end

      class SimpleDescriptor < Solrizer::Descriptor
        def name_and_converter(field_name, field_type)
          if field_type == :date
            [field_name + '_d']
          else
            super
          end
        end
      end

      class FungibleDescriptor < TestMapper0::Descriptors0::FungibleDescriptor
        def name_and_converter(field_name, field_type)
          [field_name + fungible_type(field_type)]
        end

        def fungible_type(type)
            case type
            when :garble
              '_f4'
            when :integer
              '_f5'
            else
              super
            end
        end
      end
    end
    self.descriptors = [Descriptors1, Descriptors0, Solrizer::DefaultDescriptors]
  end
  
  before(:each) do
    @mapper = TestMapper0.new
  end
  
  after(:all) do
  end
  
  # --- Tests ----
  
  it "should handle the id field" do
    @mapper.id_field.should == 'ident'
  end
  
  describe '.solr_name' do
    it "should map based on index_as" do
      @mapper.solr_name('bar', :string, :edible).should == 'bar_food'
      @mapper.solr_name('bar', :string, :laughable).should == 'bar_haha'
    end

    it "should default the index_type to :searchable" do
      @mapper.solr_name('foo', :string).should == 'foo_si'
    end
    
    it "should map based on data type" do
      @mapper.solr_name('foo', :integer, :fungible).should == 'foo_f1'
      @mapper.solr_name('foo', :garble,  :fungible).should == 'foo_f2'  # based on type.default
      @mapper.solr_name('foo', :date,    :fungible).should == 'foo_f0'  # type.date falls through to container
    end
  
    it "should return nil for an unknown index types" do
      lambda { 
        @mapper.solr_name('foo', :string, :blargle)
      }.should raise_error(Solrizer::UnknownIndexMacro, "Unable to find `blargle' in [TestMapper0::Descriptors0, Solrizer::DefaultDescriptors]")
    end
    
    it "should allow subclasses to selectively override suffixes" do
      @mapper = TestMapper1.new
      @mapper.solr_name('foo', :date).should == 'foo_d'   # override
      @mapper.solr_name('foo', :string).should == 'foo_si' # from super
      @mapper.solr_name('foo', :integer, :fungible).should == 'foo_f5'  # override on data type
      @mapper.solr_name('foo', :garble,  :fungible).should == 'foo_f4'  # override on data type
      @mapper.solr_name('foo', :fratz,   :fungible).should == 'foo_f2'  # from super
      @mapper.solr_name('foo', :date,    :fungible).should == 'foo_f0'  # super definition picks up override on index type
    end
    
    it "should support field names as symbols" do
      @mapper.solr_name(:active_fedora_model, :symbol).should == "active_fedora_model_si"
    end
    
    it "should support scenarios where field_type is nil" do
      mapper = Solrizer::FieldMapper::Default.new
      lambda { mapper.solr_name(:heifer, nil, :searchable)}.should raise_error Solrizer::InvalidIndexDescriptor
    end
  end
  
  describe '.solr_names_and_values' do
    it "should map values based on index_as" do
      @mapper.solr_names_and_values('foo', 'bar', :string, [:searchable, :laughable, :edible]).should == {
        'foo_s'    => ['bar'],
        'foo_food' => ['bar'],
        'foo_haha' => ["Knock knock. Who's there? Bar. Bar who?"]
      }
    end
    
    it "should apply mappings based on data type" do
      @mapper.solr_names_and_values('foo', 'bar', :integer, [:searchable, :laughable]).should == {
        'foo_s'     => ['bar'],
        'foo_ihaha' => ["How many foos does it take to screw in a light bulb? Bar."]
      }
    end
    
    it "should raise error on unknown index types" do
      lambda { 
        @mapper.solr_names_and_values('foo', 'bar', :string, [:blargle])
      }.should raise_error(Solrizer::UnknownIndexMacro, "Unable to find `blargle' in [TestMapper0::Descriptors0, Solrizer::DefaultDescriptors]")
    end
    
    it "should generate multiple mappings when two return the _same_ solr name but _different_ values" do
      @mapper.solr_names_and_values('roll', 'rock', :date, [:unstemmed_searchable, :searchable]).should == {
        'roll_s' => ["rock o'clock", 'rock']
      }
    end
    
    it "should not generate multiple mappings when two return the _same_ solr name and the _same_ value" do
      @mapper.solr_names_and_values('roll', 'rock', :string, [:unstemmed_searchable, :searchable]).should == {
        'roll_s' => ['rock'],
      }
    end
  end

  describe "#load_mappings" do 
    before(:each) do
      class TestMapperLoading < Solrizer::FieldMapper
      end
    end
    it "should take mappings file as an optional argument" do
      file_path = File.join(File.dirname(__FILE__), "..", "fixtures","test_solr_mappings.yml")
  	  TestMapperLoading.load_mappings(file_path)
  	  mapper = TestMapperLoading.new
      mappings_from_file = YAML::load(File.open(file_path))
      mapper.id_field.should == "pid"
      mapper.mappings[:edible].opts[:default].should == true
      mapper.mappings[:edible].data_types[:boolean].opts[:suffix].should == "_edible_bool"
      mappings_from_file["edible"].each_pair do |k,v|
        mapper.mappings[:edible].data_types[k.to_sym].opts[:suffix].should == v        
      end
      mapper.mappings[:displayable].opts[:suffix].should == mappings_from_file["displayable"]
      mapper.mappings[:facetable].opts[:suffix].should == mappings_from_file["facetable"]
      mapper.mappings[:sortable].opts[:suffix].should == mappings_from_file["sortable"]
	  end
	  it 'should default to using the mappings from config/solr_mappings.yml' do
	    TestMapperLoading.load_mappings
  	  mapper = TestMapperLoading.new
  	  default_file_path = File.join(File.dirname(__FILE__), "..", "..","config","solr_mappings.yml")
      mappings_from_file = YAML::load(File.open(default_file_path))
      mapper.id_field.should == mappings_from_file["id"]
      mappings_from_file["searchable"].each_pair do |k,v|
        mapper.mappings[:searchable].data_types[k.to_sym].opts[:suffix].should == v        
      end
      mapper.mappings[:displayable].opts[:suffix].should == mappings_from_file["displayable"]
      mapper.mappings[:facetable].opts[:suffix].should == mappings_from_file["facetable"]
      mapper.mappings[:sortable].opts[:suffix].should == mappings_from_file["sortable"]
    end
    it "should wipe out pre-existing mappings without affecting other FieldMappers" do
      TestMapperLoading.load_mappings
      file_path = File.join(File.dirname(__FILE__), "..", "fixtures","test_solr_mappings.yml")
  	  TestMapperLoading.load_mappings(file_path)
  	  mapper = TestMapperLoading.new
  	  mapper.mappings[:searchable].should be_nil
  	  default_mapper = Solrizer::FieldMapper::Default.new
  	  default_mapper.mappings[:searchable].should_not be_nil
  	end
  	it "should raise an informative error if the yaml file is structured improperly"
  	it "should raise an informative error if there is no YAML file"
	end
  
  describe Solrizer::FieldMapper::Default do
    before(:each) do
      @mapper = Solrizer::FieldMapper::Default.new
    end
  	
    it "should call the id field 'id'" do
      @mapper.id_field.should == 'id'
    end
    
    it "should not apply mappings for searchable by default" do
      # Just sanity check a couple; copy & pasting all data types is silly
      @mapper.solr_names_and_values('foo', 'bar', :string, []).should == {  }
      @mapper.solr_names_and_values('foo', "1", :integer, []).should == { }
    end

    it "should support full ISO 8601 dates" do
      @mapper.solr_names_and_values('foo', "2012-11-06",              :date, [:searchable]).should == { 'foo_dtsi' =>["2012-11-06T00:00:00Z"] }
      @mapper.solr_names_and_values('foo', "November 6th, 2012",      :date, [:searchable]).should == { 'foo_dtsi' =>["2012-11-06T00:00:00Z"] }
      @mapper.solr_names_and_values('foo', Date.parse("6 Nov. 2012"), :date, [:searchable]).should == { 'foo_dtsi' =>["2012-11-06T00:00:00Z"] }
      @mapper.solr_names_and_values('foo', '', :date, [:searchable]).should == { 'foo_dtsi' => [] }
    end
    
    it "should support displayable, facetable, sortable, unstemmed" do
      @mapper.solr_names_and_values('foo', 'bar', :string, [:searchable, :displayable, :facetable, :sortable, :unstemmed_searchable]).should == {
        "foo_tesim" => ["bar"], #searchable
        "foo_sim" => ["bar"], #displayable, facetable
        "foo_ssi" => ["bar"], #sortable
        "foo_tim" => ["bar"] #unstemmed_searchable
      }
    end
  end
end
