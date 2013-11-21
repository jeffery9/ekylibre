# = Informations
#
# == License
#
# Ekylibre - Simple ERP
# Copyright (C) 2009-2013 Brice Texier, Thibaud Merigon
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see http://www.gnu.org/licenses.
#
# == Table: product_nature_variants
#
#  active                 :boolean          not null
#  category_id            :integer          not null
#  commercial_description :text
#  commercial_name        :string(255)      not null
#  contour                :string(255)
#  created_at             :datetime         not null
#  creator_id             :integer
#  derivative_of          :string(120)
#  horizontal_rotation    :integer          default(0), not null
#  id                     :integer          not null, primary key
#  lock_version           :integer          default(0), not null
#  name                   :string(255)
#  nature_id              :integer          not null
#  nature_name            :string(255)      not null
#  number                 :string(255)
#  picture_content_type   :string(255)
#  picture_file_name      :string(255)
#  picture_file_size      :integer
#  picture_updated_at     :datetime
#  reference_name         :string(255)
#  unit_name              :string(255)      not null
#  updated_at             :datetime         not null
#  updater_id             :integer
#  variety                :string(120)      not null
#

class ProductNatureVariant < Ekylibre::Record::Base
  # attr_accessible :active, :commercial_name, :nature_id, :nature_name, :unit_name, :name, :indicator_data_attributes, :products_attributes, :prices_attributes
  enumerize :variety,       in: Nomen::Varieties.all
  enumerize :derivative_of, in: Nomen::Varieties.all
  belongs_to :nature, class_name: "ProductNature", inverse_of: :variants
  belongs_to :category, class_name: "ProductNatureCategory", inverse_of: :variants
  has_many :products, foreign_key: :variant_id
  has_many :indicator_data, class_name: "ProductNatureVariantIndicatorDatum", foreign_key: :variant_id
  has_many :prices, class_name: "CatalogPrice", foreign_key: :variant_id
  #[VALIDATORS[ Do not edit these lines directly. Use `rake clean:validations`.
  validates_numericality_of :horizontal_rotation, :picture_file_size, allow_nil: true, only_integer: true
  validates_length_of :derivative_of, :variety, allow_nil: true, maximum: 120
  validates_length_of :commercial_name, :contour, :name, :nature_name, :number, :picture_content_type, :picture_file_name, :reference_name, :unit_name, allow_nil: true, maximum: 255
  validates_inclusion_of :active, in: [true, false]
  validates_presence_of :category, :commercial_name, :horizontal_rotation, :nature, :nature_name, :unit_name, :variety
  #]VALIDATORS]

  delegate :matching_model, :indicators_array, :population_frozen?, :population_modulo, :frozen_indicators_array, :variable_indicators_array, to: :nature
  delegate :variety, :derivative_of, to: :nature, prefix: true
  delegate :asset_account, :product_account, :charge_account, :stock_account, to: :category

  accepts_nested_attributes_for :products, :reject_if => :all_blank, :allow_destroy => true
  accepts_nested_attributes_for :indicator_data, :reject_if => :all_blank, :allow_destroy => true
  accepts_nested_attributes_for :prices, :reject_if => :all_blank, :allow_destroy => true
  acts_as_numbered

  has_attached_file :picture, {
    :url => '/backend/:class/:id/picture/:style',
    :path => ':rails_root/private/:class/:attachment/:id_partition/:style.:extension',
    :styles => {
      :thumb => ["64x64#", :jpg],
      :identity => ["180x180#", :jpg]
      # :large => ["600x600", :jpg]
    }
  }

  # default_scope -> { order(:name) }

  scope :saleables, -> { joins(:nature).merge(ProductNature.saleables) }
  scope :deliverables, -> { joins(:nature).merge(ProductNature.stockables) }

  scope :of_variety, Proc.new { |*varieties|
    where(variety: varieties.collect{|v| Nomen::Varieties.all(v.to_sym) }.flatten.map(&:to_s).uniq)
  }
  scope :derivative_of, Proc.new { |*varieties|
    where(derivative_of: varieties.collect{|v| Nomen::Varieties.all(v.to_sym) }.flatten.map(&:to_s).uniq)
  }
  scope :can, Proc.new { |*abilities|
    where(nature_id: ProductNature.can(*abilities))
  }

  scope :of_natures, lambda { |*natures|
    natures.flatten!
    for nature in natures
      raise ArgumentError.new("Expected Product Nature, got #{nature.class.name}:#{nature.inspect}") unless nature.is_a?(ProductNature)
    end
    where("#{ProductNatureVariant.table_name}.nature_id IN (?)", natures.map(&:id))
  }

  protect(on: :destroy) do
    self.products.count.zero? and self.prices.count.zero?
  end

  before_validation on: :create do
    if self.nature
      self.category_id = self.nature.category_id
      self.nature_name ||= self.nature.name
      # self.variable_indicators ||= self.nature.indicators
      self.name ||= self.nature_name
      self.variety ||= self.nature.variety
      if self.derivative_of.blank? and self.nature.derivative_of
        self.derivative_of ||= self.nature.derivative_of
      end
      #if indicator = self.indicators_array.first
      #  self.usage_indicator ||= indicator.name
      #end
    end
    self.commercial_name ||= self.name
    #if item = Nomen::Indicators.find(self.usage_indicator)
    #  self.usage_indicator_unit = item.unit
    #  self.sale_indicator ||= self.usage_indicator
    #  self.sale_indicator_unit ||= self.usage_indicator_unit
    #  self.purchase_indicator ||= self.usage_indicator
    #  self.purchase_indicator_unit ||= self.usage_indicator_unit
    #end
    #if item = Nomen::Indicators.find(self.sale_indicator)
    # self.sale_indicator_unit ||= item.unit
    #end
    #if item = Nomen::Indicators.find(self.purchase_indicator)
    # self.purchase_indicator_unit ||= item.unit
    #end

  end

  validate do
    if self.nature
      unless Nomen::Varieties.all(self.nature_variety).include?(self.variety.to_s)
        errors.add(:variety, :invalid)
      end
      if self.derivative_of
        unless Nomen::Varieties.all(self.nature_derivative_of).include?(self.derivative_of.to_s)
          errors.add(:derivative_of, :invalid)
        end
      end
    end
  end

  def deliverable?
    self.nature.deliverable?
  end

  def purchasable?
    self.nature.purchasable?
  end

  def saleable?
    self.nature.saleable?
  end

  def subscribing?
    self.nature.subscribing?
  end

  #validate do
  # Check that unit match indicator's unit
  #for mode in [:usage, :sale, :purchase]
  #  unit = self.send("#{mode}_indicator_unit").to_s
  # if item = Nomen::Indicators[self.send("#{mode}_indicator")] and !unit.blank?
  #   if Measure.dimension(item.unit) != Measure.dimension(unit)
  #     errors.add(:"#{mode}_indicator_unit", :invalid)
  #    end
  #  end
  #end
  #end

  # Measure a product for a given indicator
  def is_measured!(indicator, value, options = {})
    unless Nomen::Indicators[indicator]
      raise ArgumentError.new("Unknown indicator #{indicator.inspect}")
    end
    datum = self.indicator_data.new(:indicator => indicator)
    datum.value = value
    datum.save!
    return datum
  end

  # Return the indicator datum
  def indicator(indicator, options = {})
    created_at = options[:at] || Time.now
    return self.indicator_data.where(:indicator => indicator.to_s).where("created_at <= ?", created_at).reorder("created_at DESC").first
  end

  # check if a variant has an indicator which is frozen or not
  def frozen?(indicator)
    frozen_indicator = self.indicator(indicator)
    if frozen_indicator.computation_method == "frozen"
      return true
    else
      return false
    end
  end


  # Returns indicators for a set of product
  def self.indicator(name, options = {})
    created_at = options[:at] || Time.now
    ProductNatureVariantIndicatorDatum.where("id IN (SELECT p1.id FROM #{self.indicator_table_name(name)} AS p1 LEFT OUTER JOIN #{self.indicator_table_name(name)} AS p2 ON (p1.variant_id = p2.variant_id AND (p1.created_at < p2.created_at OR (p1.created_at = p2.created_at AND p1.id < p2.id)) AND p2.created_at <= ?) WHERE p1.created_at <= ? AND p1.variant_id IN (?) AND p2 IS NULL)", created_at, created_at, self.pluck(:id))
  end


  # Find or import variant from nomenclature with given attributes
  # variety and derivative_of only are accepted for now
  def self.find_or_import!(variety, options = {})
    variants = of_variety(variety)
    if derivative_of = options[:derivative_of]
      variants = variants.derivative_of(derivative_of)
    end
    if variants.empty?
      # Flatten variants for search
      nomenclature = Nomen::ProductNatureVariants.list.collect do |item|
        nature = Nomen::ProductNatures[item.nature]
        h = {reference_name: item.name, variety: Nomen::Varieties[item.variety || nature.variety]} # , nature: nature
        if d = Nomen::Varieties[item.derivative_of || nature.derivative_of]
          h[:derivative_of] = d
        end
        h
      end
      # puts [variety, derivative_of].inspect
      # puts "NOMENCLATURE: " + nomenclature.inspect
      # Filter and imports
      filtereds = nomenclature.select do |item|
        item[:variety].include?(variety) and
          ((derivative_of and item[:derivative_of] and item[:derivative_of].include?(derivative_of)) or (derivative_of.blank? and item[:derivative_of].blank?))
      end
      # puts "FILTEREDS: " + filtereds.inspect
      filtereds.each do |item|
        # puts "Import #{item[:reference_name]}!"
        import_from_nomenclature(item[:reference_name])
      end
    end
    return variants.reload
  end


  # Load a product nature variant from product nature variant nomenclature
  def self.import_from_nomenclature(reference_name)
    unless item = Nomen::ProductNatureVariants[reference_name]
      raise ArgumentError, "The product_nature_variant #{reference_name.inspect} is not known"
    end
    unless nature_item = Nomen::ProductNatures[item.nature]
      raise ArgumentError, "The nature of the product_nature_variant #{item.nature.inspect} is not known"
    end
    unless variant = ProductNatureVariant.find_by(reference_name: reference_name.to_s)
      attributes = {
        :name => item.human_name,
        :active => true,
        :nature => ProductNature.find_by_reference_name(item.nature) || ProductNature.import_from_nomenclature(item.nature),
        :reference_name => item.name,
        :unit_name => I18n.translate("nomenclatures.product_nature_variants.choices.unit_name.#{item.unit_name}"),
        # :frozen_indicators => item.frozen_indicators_values.to_s,
        :variety => item.variety || nil,
        :derivative_of => item.derivative_of || nil
      }
      variant = self.create!(attributes)
    end

    if variant and !item.frozen_indicators_values.to_s.blank?
      # create frozen indicator for each pair indicator, value ":population => 1unity"
      item.frozen_indicators_values.to_s.strip.split(/[[:space:]]*\,[[:space:]]*/)
        .collect{|i| i.split(/[[:space:]]*\:[[:space:]]*/)}.each do |i|
        variant.is_measured!(i.first.strip.downcase.to_sym, i.second)
      end
    end

    return variant
  end

  # Get indicator value
  # if option :at specify at which moment
  # if option :datum is true, it returns the ProductNatureVariantIndicatorDatum record
  # if option :interpolate is true, it returns the interpolated value
  # :interpolate and :datum options are incompatible
  def method_missing(method_name, *args)
    return super unless Nomen::Indicators.all.include?(method_name.to_s)
    options = (args[-1].is_a?(Hash) ? args.delete_at(-1) : {})
    created_at = args.shift || options[:at] || Time.now
    indicator = Nomen::Indicators.items[method_name]

    if options[:interpolate]
      if [:measure, :decimal].include?(indicator.datatype)
        raise NotImplementedError.new("Interpolation is not available for now")
      end
      raise StandardError("Can not use :interpolate option with #{indicator.datatype.inspect} datatype")
    else
      if datum = self.indicator(indicator.name.to_s, :at => created_at)
        x = datum.value
        x.define_singleton_method(:created_at) do
          created_at
        end
        variant_id = self.id
        x.define_singleton_method(:variant_id) do
          variant_id
        end
        return x
      end
    end
    return nil
  end

  # Give the indicator table name
  def self.indicator_table_name(indicator)
    ProductNatureVariantIndicatorDatum.table_name
  end

end
