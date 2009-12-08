# == Schema Information
#
# Table name: purchase_orders
#
#  accounted         :boolean       not null
#  amount            :decimal(16, 2 default(0.0), not null
#  amount_with_taxes :decimal(16, 2 default(0.0), not null
#  comment           :text          
#  company_id        :integer       not null
#  created_at        :datetime      not null
#  created_on        :date          
#  creator_id        :integer       
#  dest_contact_id   :integer       
#  id                :integer       not null, primary key
#  lock_version      :integer       default(0), not null
#  moved_on          :date          
#  number            :string(64)    not null
#  planned_on        :date          
#  shipped           :boolean       not null
#  supplier_id       :integer       not null
#  updated_at        :datetime      not null
#  updater_id        :integer       
#

class PurchaseOrder < ActiveRecord::Base
  belongs_to :company
  belongs_to :dest_contact, :class_name=>Contact.name
  belongs_to :supplier, :class_name=>Entity.name
  has_many :lines, :class_name=>PurchaseOrderLine.name, :foreign_key=>:order_id
  has_many :payment_parts, :as=>:expense

  validates_presence_of :planned_on, :created_on
  attr_readonly :company_id

  ## shipped used as received

  def before_validation
    self.created_on ||= Date.today
    if self.number.blank?
      #last = self.supplier.purchase_orders.find(:first, :order=>"number desc")
      last = self.company.purchase_orders.find(:first, :order=>"number desc")
      self.number = if last
                      last.number.succ!
                    else
                      '00000001'
                    end
    end


    self.amount = 0
    self.amount_with_taxes = 0
     for line in self.lines
       self.amount += line.amount
       self.amount_with_taxes += line.amount_with_taxes
     end
  end

  def after_create
    self.supplier.add_event(:purchase_order, self.updater_id) if self.updater
  end
  
  def refresh
    self.save
  end

  def stocks_moves_create
    locations = StockLocation.find_all_by_company_id(self.company_id)
    for line in self.lines
      if locations.size == 1
        line.update_attributes!(:location_id=>locations[0].id)
      end
      StockMove.create!(:name=>tc(:purchase)+"  "+self.number, :quantity=>line.quantity, :location_id=>line.location_id, :product_id=>line.product_id, :planned_on=>self.planned_on, :company_id=>line.company_id, :virtual=>true, :input=>true, :origin_type=>PurchaseOrder.to_s, :origin_id=>self.id, :generated=>true)
    end
  end

  def real_stocks_moves_create
    for line in self.lines
      StockMove.create!(:name=>tc(:purchase)+"  "+line.order.number, :quantity=>line.quantity, :location_id=>line.location_id, :product_id=>line.product_id, :planned_on=>self.planned_on, :moved_on=>Date.today, :company_id=>line.company_id, :virtual=>false, :input=>true, :origin_type=>PurchaseOrder.to_s, :origin_id=>self.id, :generated=>true)
    end
    self.moved_on = Date.today if self.moved_on.nil?
    self.shipped = true
    self.save
  end

  def label 
     tc('label', :supplier=>self.supplier.full_name.to_s, :address=>self.dest_contact.address.to_s)
  end

  def quantity 
    ''
  end

  def payments_sum
    self.payment_parts.sum(:amount)
  end

  def editable
    if self.amount_with_taxes == 0 
      return true
    else
      return self.payments_sum != self.amount_with_taxes
    end
  end

  
  #this method saves the purchase in the accountancy module.
  def to_accountancy
    journal_purchase=  self.company.journals.find(:first, :conditions => ['nature = ?', 'purchase'],:order=>:id)
    
    financialyear = self.company.financialyears.find(:first, :conditions => ["(? BETWEEN started_on and stopped_on) AND closed=?", '%'+Date.today.to_s+'%', false])
    
     unless financialyear.nil? or journal_purchase.nil?
       
       record = self.company.journal_records.create!(:resource_id=>self.id, :resource_type=>self.class.name, :created_on=>Date.today, :printed_on => self.planned_on, :journal_id=>journal_purchase.id, :financialyear_id => financialyear.id)
       
       supplier_account = self.supplier.account(:supplier)
            
       record.add_credit(self.supplier.full_name, supplier_account.id, self.amount_with_taxes, :draft=>true)
            
       self.lines.each do |line|
        line_amount = (line.amount * line.quantity)
        
        record.add_debit('sale '+line.product.name, line.product.charge_account_id, line_amount, :draft=>true)
        
        unless line.price.tax_id.nil?
          record.add_debit(line.price.tax.name, line.price.tax.account_paid_id, line.price.tax.amount*line_amount, :draft=>true)
        end
      end
       self.update_attribute(:accounted, true)
     end
  end

  def editable
    if self.amount_with_taxes == 0 
      return true
    else
      return (self.payments_sum < self.amount_with_taxes and not self.shipped)
    end
  end

  def last_payment
    self.company.payments.find(:first, :conditions=>{:entity_id=>self.company.entity_id}, :order=>"paid_on desc")
  end


  def unpaid_amount(all=true)
    self.amount_with_taxes - self.payments_sum
  end

  def payment_entity_id
    self.company.entity.id
  end

  def usable_payments
#    self.company.payments.find(:all, :conditions=>["COALESCE(parts_amount,0)<COALESCE(amount,0) AND entity_id = ?" , self.payment_entity_id], :order=>"created_at desc")
    self.company.payments.find(:all, :conditions=>["COALESCE(parts_amount,0)<COALESCE(amount,0)"], :order=>"amount")
  end

  def status
    status = ""
    status = "critic" if self.payments_sum < self.amount_with_taxes
    status
  end

  def supplier_address
    a = self.supplier.full_name+"\n"
    a += (self.supplier.default_contact.address).gsub(/\s*\,\s*/, "\n") if self.supplier.default_contact
    a
  end

  def client_address
    a = self.company.entity.full_name+"\n"
    a += (self.dest_contact.address).gsub(/\s*\,\s*/, "\n") if self.dest_contact
    a
  end

  def taxes
    self.amount_with_taxes - self.amount
  end
  
end
