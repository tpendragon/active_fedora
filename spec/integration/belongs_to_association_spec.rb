require 'spec_helper'

describe ActiveFedora::Base do
  before do
    class Library < ActiveFedora::Base 
      has_many :books
    end

    class Book < ActiveFedora::Base 
      belongs_to :library, property: :has_constituent
    end
    class SpecialInheritedBook < Book
    end

  end
  after do
    Object.send(:remove_const, :Library)
    Object.send(:remove_const, :SpecialInheritedBook)
    Object.send(:remove_const, :Book)
  end

  let(:library) { Library.create }
  let(:book) { Book.new }

  describe "setting the id property" do
    it "should store it" do
      book.library_id = library.id
      book.library_id.should == library.id
    end

    describe "reassigning the parent_id" do
      let(:library2) { Library.create}
      before { book.library = library2 }
      it "should update the object" do
        expect(book.library).to eq library2 # cause the association to set @loaded
        library_proxy = book.send(:association_instance_get, :library)
        expect(library_proxy).to_not be_stale_target
        book.library_id = library.id
        expect(library_proxy).to be_stale_target
        expect(book.library).to eq library
      end
    end

    it "should be settable via []=" do
      book[:library_id] = library.id
      book.library_id.should == library.id
    end
  end

  describe "getting the id property" do
    it "should be accessable via []" do
      book[:library_id] = library.id
      book[:library_id].should == library.id
    end
  end

  describe "when dealing with inherited objects" do
    before do
      @library2 = Library.create
      @special_book = SpecialInheritedBook.create

      book.library = @library2
      book.save
      @special_book.library = @library2
      @special_book.save
    end

    it "should cast to the most specific class for the association" do
      @library2.books[0].class == Book
      @library2.books[1].class == SpecialInheritedBook
    end

    after do
      @library2.delete
      @special_book.delete
    end
  end

  describe "casting inheritance detailed test cases" do
    before :all do
      class SimpleObject < ActiveFedora::Base
        belongs_to :simple_collection, property: :is_part_of, class_name: 'SimpleCollection'
        belongs_to :complex_collection, property: :is_part_of, class_name: 'ComplexCollection'
      end

      class ComplexObject < SimpleObject
        belongs_to :simple_collection, property: :is_part_of, class_name: 'SimpleCollection'
        belongs_to :complex_collection, property: :is_part_of, class_name: 'ComplexCollection'
      end

      class SimpleCollection < ActiveFedora::Base
        has_many :objects, property: :is_part_of, class_name: 'SimpleObject'
        has_many :complex_objects, property: :is_part_of, class_name: 'ComplexObject'
      end

      class ComplexCollection < SimpleCollection
        has_many :objects, property: :is_part_of, class_name: 'SimpleObject'
        has_many :complex_objects, property: :is_part_of, class_name: 'ComplexObject'
      end

    end
    after :all do
      Object.send(:remove_const, :SimpleObject)
      Object.send(:remove_const, :ComplexObject)
      Object.send(:remove_const, :SimpleCollection)
      Object.send(:remove_const, :ComplexCollection)
    end

    describe "saving between the before and after hooks" do
      context "Add a complex_object into a simple_collection" do
        before do
          @simple_collection = SimpleCollection.create
          @complex_collection = ComplexCollection.create
          @complex_object = ComplexObject.create
          @simple_collection.objects = [@complex_object]
          @simple_collection.save!
          @complex_collection.save!
        end
        it "should have added the inverse relationship for the correct class" do
          @complex_object.simple_collection.should be_instance_of SimpleCollection
          @complex_object.complex_collection.should be_nil
        end
      end

      context "Add a complex_object into a complex_collection" do
        before do
          @complex_collection = ComplexCollection.create
          @complex_object = ComplexObject.create
          @complex_collection.objects = [@complex_object]
          @complex_collection.save!
        end
        it "should have added the inverse relationship for the correct class" do
          @complex_object.complex_collection.should be_instance_of ComplexCollection
          @complex_object.reload.simple_collection.should be_instance_of ComplexCollection
        end
      end

      context "Adding mixed types on a base class with a filtered has_many relationship" do
        before do
          @simple_collection = SimpleCollection.create
          @complex_object = ComplexObject.create
          @simple_object = SimpleObject.create
          @simple_collection.objects = [@complex_object, @simple_object]
          @simple_collection.save!
        end
        it "ignores objects who's classes aren't specified" do
          @simple_collection.complex_objects.size.should == 1
          @simple_collection.complex_objects[0].should be_instance_of ComplexObject
          @simple_collection.complex_objects[1].should be_nil

          @simple_collection.objects.size.should == 2
          @simple_collection.objects[0].should be_instance_of ComplexObject
          @simple_collection.objects[1].should be_instance_of SimpleObject

          @simple_object.simple_collection.should be_instance_of SimpleCollection
          @simple_object.complex_collection.should be_nil
        end
      end

      context "Adding mixed types on a subclass with a filtered has_many relationship" do
        before do
          @complex_collection = ComplexCollection.create
          @complex_object = ComplexObject.create
          @simple_object = SimpleObject.create
          @complex_collection.objects = [@complex_object, @simple_object]
          @complex_collection.save!
        end
        it "ignores objects who's classes aren't specified" do
          @complex_collection.complex_objects.size.should == 1
          @complex_collection.complex_objects[0].should be_instance_of ComplexObject
          @complex_collection.complex_objects[1].should be_nil

          @complex_collection.objects.size.should == 2
          @complex_collection.objects[0].should be_instance_of ComplexObject
          @complex_collection.objects[1].should be_instance_of SimpleObject

          @simple_object.complex_collection.should be_instance_of ComplexCollection
          @simple_object.reload.simple_collection.should be_instance_of ComplexCollection
        end
      end
    end
  end
end

