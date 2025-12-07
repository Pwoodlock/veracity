class AddCoordinatesToServers < ActiveRecord::Migration[8.0]
  def change
    add_column :servers, :latitude, :decimal, precision: 10, scale: 6
    add_column :servers, :longitude, :decimal, precision: 10, scale: 6
  end
end
