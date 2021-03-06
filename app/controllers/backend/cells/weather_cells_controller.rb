class Backend::Cells::WeatherCellsController < Backend::Cells::BaseController

  def show
    @forecast = nil
    if zone = (params[:id] ? CultivableZone.find_by(id: params[:id]) : CultivableZone.first)
      if reading = zone.reading(:shape)
        coordinates = Charta::Geometry.new(reading.geometry_value).centroid
        http = Net::HTTP.new("api.openweathermap.org")
        http.open_timeout = 3
        http.read_timeout = 3
        res = http.get("/data/2.5/forecast/daily?lat=#{coordinates.first}&lon=#{coordinates.second}&cnt=14&mode=json")

        json = JSON.load(res.body) rescue nil
        unless json.nil?

          @forecast = json.deep_symbolize_keys

          if @forecast[:cod] == '200'
            @forecast[:list] = @forecast[:list].collect do |day|
              day.deep_symbolize_keys!
              {
                  at: Time.at(day[:dt]),
                  temperatures: [:day, :night, :min, :max, :eve, :morn].inject({}) do |hash, key|
                    hash[key] = (day[:temp][key] || 0).in_kelvin
                    hash
                  end,
                  pressure: day[:pressure].in_hectopascal,
                  humidity: (day[:humidity] || 0).in_percent,
                  wind_speed: (day[:speed] || 0).in_meter_per_second,
                  wind_direction: (day[:deg] || 0).in_degree,
                  rain: (day[:rain] || 0).in_millimeter,
                  clouds: (day[:rain] || 0).in_percent,
                  # weather: day[:weather]
              }
            end
          else
            @forecast = nil
          end

        end

      end
    end
  rescue Net::OpenTimeout => e
    @forecast = nil
    logger.warn "Net::OpenTimeout: Cannot open service OpenWeatherMap in time (#{e.message})"
  rescue Net::ReadTimeout => e
    @forecast = nil
    logger.warn "Net::ReadTimeout: Cannot read service OpenWeatherMap in time (#{e.message})"
  end

end
