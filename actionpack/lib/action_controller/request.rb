module ActionController
  # These methods are available in both the production and test Request objects.
  class AbstractRequest
    cattr_accessor :relative_url_root
    
    # Returns both GET and POST parameters in a single hash.
    def parameters
      @parameters ||= request_parameters.merge(query_parameters).merge(path_parameters).with_indifferent_access
    end

    # Returns the HTTP request method as a lowercase symbol (:get, for example)
    def method
      env['REQUEST_METHOD'].downcase.to_sym
    end

    # Is this a GET request?  Equivalent to request.method == :get
    def get?
      method == :get
    end

    # Is this a POST request?  Equivalent to request.method == :post
    def post?
      method == :post
    end

    # Is this a PUT request?  Equivalent to request.method == :put
    def put?
      method == :put
    end

    # Is this a DELETE request?  Equivalent to request.method == :delete
    def delete?
      method == :delete
    end

    # Is this a HEAD request?  Equivalent to request.method == :head
    def head?
      method == :head
    end

    # Determine whether the body of a POST request is URL-encoded (default),
    # XML, or YAML by checking the Content-Type HTTP header:
    #
    #   Content-Type        Post Format
    #   application/xml     :xml
    #   text/xml            :xml
    #   application/x-yaml  :yaml
    #   text/x-yaml         :yaml
    #   *                   :url_encoded
    #
    # For backward compatibility, the post format is extracted from the
    # X-Post-Data-Format HTTP header if present.
    def post_format
      if env['HTTP_X_POST_DATA_FORMAT']
        env['HTTP_X_POST_DATA_FORMAT'].downcase.to_sym
      else
        case env['CONTENT_TYPE'].to_s.downcase
          when 'application/xml', 'text/xml'        then :xml
          when 'application/x-yaml', 'text/x-yaml'  then :yaml
          else :url_encoded
        end
      end
    end

    # Is this a POST request formatted as XML or YAML?
    def formatted_post?
      [ :xml, :yaml ].include?(post_format) && post?
    end

    # Is this a POST request formatted as XML?
    def xml_post?
      post_format == :xml && post?
    end

    # Is this a POST request formatted as YAML?
    def yaml_post?
      post_format == :yaml && post?
    end

    # Returns true if the request's "X-Requested-With" header contains
    # "XMLHttpRequest". (The Prototype Javascript library sends this header with
    # every Ajax request.)
    def xml_http_request?
      not /XMLHttpRequest/i.match(env['HTTP_X_REQUESTED_WITH']).nil?
    end
    alias xhr? :xml_http_request?

    # Determine originating IP address.  REMOTE_ADDR is the standard
    # but will fail if the user is behind a proxy.  HTTP_CLIENT_IP and/or
    # HTTP_X_FORWARDED_FOR are set by proxies so check for these before
    # falling back to REMOTE_ADDR.  HTTP_X_FORWARDED_FOR may be a comma-
    # delimited list in the case of multiple chained proxies; the first is
    # the originating IP.
    def remote_ip
      return env['HTTP_CLIENT_IP'] if env.include? 'HTTP_CLIENT_IP'

      if env.include? 'HTTP_X_FORWARDED_FOR' then
        remote_ips = env['HTTP_X_FORWARDED_FOR'].split(',').reject do |ip|
            ip =~ /^unknown$|^(10|172\.(1[6-9]|2[0-9]|30|31)|192\.168)\./i
        end

        return remote_ips.first.strip unless remote_ips.empty?
      end

      return env['REMOTE_ADDR']
    end

    # Returns the domain part of a host, such as rubyonrails.org in "www.rubyonrails.org". You can specify
    # a different <tt>tld_length</tt>, such as 2 to catch rubyonrails.co.uk in "www.rubyonrails.co.uk".
    def domain(tld_length = 1)
      host.split('.').last(1 + tld_length).join('.')
    end

    # Returns all the subdomains as an array, so ["dev", "www"] would be returned for "dev.www.rubyonrails.org".
    # You can specify a different <tt>tld_length</tt>, such as 2 to catch ["www"] instead of ["www", "rubyonrails"]
    # in "www.rubyonrails.co.uk".
    def subdomains(tld_length = 1)
      parts = host.split('.')
      parts[0..-(tld_length+2)]
    end

    # Receive the raw post data. 
    # This is useful for services such as REST, XMLRPC and SOAP 
    # which communicate over HTTP POST but don't use the traditional parameter format. 
    def raw_post
      env['RAW_POST_DATA']
    end
    
    def request_uri
      unless env['REQUEST_URI'].nil?
        (%r{^\w+\://[^/]+(/.*|$)$} =~ env['REQUEST_URI']) ? $1 : env['REQUEST_URI'] # Remove domain, which webrick puts into the request_uri.
      else  # REQUEST_URI is blank under IIS - get this from PATH_INFO and SCRIPT_NAME
        script_filename = env["SCRIPT_NAME"].to_s.match(%r{[^/]+$})
        request_uri = env["PATH_INFO"]
        request_uri.sub!(/#{script_filename}\//, '') unless script_filename.nil?
        request_uri += '?' + env["QUERY_STRING"] unless env["QUERY_STRING"].nil? || env["QUERY_STRING"].empty?
        return request_uri
      end
    end

    # Return 'https://' if this is an SSL request and 'http://' otherwise.
    def protocol
      env["HTTPS"] == "on" ? 'https://' : 'http://'
    end

    # Is this an SSL request?
    def ssl?
      protocol == 'https://'
    end
  
    # Returns the interpreted path to requested resource after all the installation directory of this application was taken into account
    def path
      path = (uri = request_uri) ? uri.split('?').first : ''

      # Cut off the path to the installation directory if given
      if root = relative_url_root
        path[root.length..-1]
      else
        path
      end
    end    
    
    # Returns the path minus the web server relative installation directory.
    # This method returns nil unless the web server is apache.
    def relative_url_root
      @@relative_url_root ||= File.dirname(env["SCRIPT_NAME"].to_s).gsub(/(^\.$|^\/$)/, '') if server_software == 'apache'
    end

    # Returns the port number of this request as an integer.
    def port
      env['SERVER_PORT'].to_i
    end

    # Returns a port suffix like ":8080" if the port number of this request
    # is not the default HTTP port 80 or HTTPS port 443.
    def port_string
      (protocol == 'http://' && port == 80) || (protocol == 'https://' && port == 443) ? '' : ":#{port}"
    end

    # Returns a host:port string for this request, such as example.com or
    # example.com:8080.
    def host_with_port
      env['HTTP_HOST'] || host + port_string
    end
  
    def path_parameters=(parameters)
      @path_parameters = parameters
      @symbolized_path_parameters = @parameters = nil
    end
    
    def symbolized_path_parameters
      @symbolized_path_parameters ||= path_parameters.symbolize_keys
    end

    def path_parameters
      @path_parameters ||= {}
    end

    # Returns the lowercase name of the HTTP server software.
    def server_software
      (env['SERVER_SOFTWARE'] && /^([a-zA-Z]+)/ =~ env['SERVER_SOFTWARE']) ? $1.downcase : nil
    end

    #--
    # Must be implemented in the concrete request
    #++
    def query_parameters
    end

    def request_parameters
    end

    def env
    end

    def host
    end

    def cookies
    end

    def session
    end

    def reset_session
    end    
  end
end
