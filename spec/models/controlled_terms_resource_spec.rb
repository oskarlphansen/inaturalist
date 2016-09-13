require "spec_helper.rb"

describe ControlledTermsResource do

  it "validates presence of resource" do
    expect{ ControlledTermsResource.make!(resource: nil) }.to raise_error(
      ActiveRecord::RecordInvalid, /Resource can't be blank/)
  end

  it "validates existence of resource" do
    expect{
      ControlledTermsResource.make!(resource: nil, resource_type: "Observation", resource_id: 9999)
    }.to raise_error(ActiveRecord::RecordInvalid, /Resource can't be blank/)
  end

  it "validates presence of controlled_attribute_id" do
    expect{ ControlledTermsResource.make!(controlled_attribute: nil) }.to raise_error(
      ActiveRecord::RecordInvalid, /Controlled attribute can't be blank/)
  end

  it "validates attribute is an attribute" do
    atr = ControlledTerm.make!(is_value: true)
    expect{ ControlledTermsResource.make!(controlled_attribute: atr) }.to raise_error(
      ActiveRecord::RecordInvalid, /Controlled attribute must be an attribute/)
  end

  it "validates value is a value" do
    val = ControlledTerm.make!
    expect{ ControlledTermsResource.make!(controlled_value: val) }.to raise_error(
      ActiveRecord::RecordInvalid, /Controlled value must be a value/)
  end

  it "validates attribute belongs to value" do
    expect{
      ControlledTermsResource.make!(
        controlled_attribute: ControlledTerm.make!,
        controlled_value: ControlledTerm.make!(is_value: true)
      )
    }.to raise_error(ActiveRecord::RecordInvalid, /Controlled value must belong to attribute/)
  end

  it "validates attribute belongs to taxon" do
    animalia = Taxon.make!(name: "Animalia")
    mammalia = Taxon.make!(name: "Mammalia", parent: animalia)
    AncestryDenormalizer.denormalize
    obs = Observation.make!(taxon: animalia)
    atr = ControlledTerm.make!(valid_within_taxon: mammalia)
    ctv = ControlledTermValue.make!(controlled_attribute: atr)
    expect{
      ControlledTermsResource.make!(
        resource: obs,
        controlled_attribute: atr,
        controlled_value: atr.values.first
      )
    }.to raise_error(ActiveRecord::RecordInvalid, /Controlled attribute must belong to taxon/)
  end

  it "validates value belongs to taxon" do
    animalia = Taxon.make!(name: "Animalia")
    mammalia = Taxon.make!(name: "Mammalia", parent: animalia)
    AncestryDenormalizer.denormalize
    obs = Observation.make!(taxon: animalia)
    atr = ControlledTerm.make!
    val = ControlledTerm.make!(valid_within_taxon: mammalia, is_value: true)
    ctv = ControlledTermValue.make!(controlled_attribute: atr, controlled_value: val)
    expect{
      ControlledTermsResource.make!(
        resource: obs,
        controlled_attribute: atr,
        controlled_value: val
      )
    }.to raise_error(ActiveRecord::RecordInvalid, /Controlled value must belong to taxon/)
  end

  it "validates uniqueness of controlled_value within resource and attribute" do
    atr = ControlledTerm.make!
    val = ControlledTerm.make!(is_value: true)
    atr.controlled_term_values.create(controlled_value: val)
    original = ControlledTermsResource.make!(
      controlled_attribute: atr,
      controlled_value: val
    )
    expect{
      ControlledTermsResource.make!(
        resource: original.resource,
        controlled_attribute: atr,
        controlled_value: val
      )
    }.to raise_error(ActiveRecord::RecordInvalid, /Controlled value has already been taken/)
  end

  it "creates valid instances" do
    atr = ControlledTerm.make!
    val = ControlledTerm.make!(is_value: true)
    atr.controlled_term_values.create(controlled_value: val)
    # ctv = ControlledTermValue.make!(controlled_attribute: atr, controlled_value: val)
    expect{
      ControlledTermsResource.make!(
        controlled_attribute: atr,
        controlled_value: val
      )
    }.to_not raise_error
    expect(ControlledTermsResource.count).to eq 1
  end

end
