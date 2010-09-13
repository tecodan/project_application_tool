module DateParamsParser
  def self.parse(hash, key)
    i1 = hash.delete "#{key.to_s}(1i)"
    i2 = hash.delete "#{key.to_s}(2i)"
    i3 = hash.delete "#{key.to_s}(3i)"
    if i1.present? && i2.present? && i3.present?
      begin
        hash[key.to_sym] = Date.new(i1.to_i, i2.to_i, i3.to_i)
      rescue ArgumentError => ex # if Date.new raises an exception on an invalid date
        hash[key.to_sym] = Time.local(i1.to_i, i2.to_i, i3.to_i).to_date # we instantiate Time object and convert it back to a date thus using Time's logic in handling invalid dates
      end
    end
  end
end
