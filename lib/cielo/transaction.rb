#encoding: utf-8
module Cielo
  class Transaction

    def initialize
      @connection = Cielo::Connection.new
    end

    # inicia uma nova transação para processamento Buy Page Cielo
    def create!(parameters={})
      create_parameters(parameters)
      message = xml_builder("requisicao-transacao") do |xml|
        xml.tag!("dados-ec") do
          xml.numero Cielo.numero_afiliacao
          xml.chave Cielo.chave_acesso
        end
        xml.tag!("dados-pedido") do
          [:numero, :valor, :moeda, :"data-hora", :idioma].each do |key|
            xml.tag!(key.to_s, parameters[key].to_s)
          end
        end
        xml.tag!("forma-pagamento") do
          [:bandeira, :produto, :parcelas].each do |key|
            xml.tag!(key.to_s, parameters[key].to_s)
          end
        end
        xml.tag!("url-retorno", parameters[:"url-retorno"])
        xml.autorizar parameters[:autorizar].to_s
        xml.capturar parameters[:capturar].to_s
      end
      make_request! message
    end

    # requisição do TID, inicia a transação para efetuar uma autorização direta - Buy Page Loja
    def request_tid!(parameters={})
      message = xml_builder("requisicao-tid") do |xml|
        xml.tag!("dados-ec") do
          xml.numero Cielo.numero_afiliacao
          xml.chave Cielo.chave_acesso
        end
        xml.tag!("forma-pagamento") do
          [:bandeira, :produto, :parcelas].each do |key|
            xml.tag!(key.to_s, parameters[key].to_s)
          end
        end
      end
      make_request! message
    end

    # efetua a autorização direta passando todos os dados da transação - Buy Page Loja
    def direct_auth!(parameters={})
      auth_parameters(parameters)
      message = xml_builder("requisicao-autorizacao-portador") do |xml|
        xml.tid parameters[:tid].to_s
        xml.tag!("dados-ec") do
          xml.numero Cielo.numero_afiliacao
          xml.chave Cielo.chave_acesso
        end
        xml.tag!("dados-cartao") do
          [:numero, :validade, :indicador, :"codigo-seguranca", :"nome-portador"].each do |key|
            #if key == :numero then
            #  xml.tag!(key.to_s, parameters[:numcartao].to_s)
            #else
            xml.tag!(key.to_s, parameters[("cartao-" + key.to_s).to_sym].to_s)
            #end
          end
        end
        xml.tag!("dados-pedido") do
          [:numero, :valor, :moeda, :"data-hora", :idioma].each do |key|
            xml.tag!(key.to_s, parameters[key].to_s)
          end
        end
        xml.tag!("forma-pagamento") do
          [:bandeira, :produto, :parcelas].each do |key|
            xml.tag!(key.to_s, parameters[key].to_s)
          end
        end
        xml.tag!("capturar-automaticamente", parameters[:capturar].to_s)
      end
      make_request! message
    end

    # efetua uma consulta e obtem os dados da transação
    def verify!(cielo_tid)
      return nil unless cielo_tid
      message = xml_builder("requisicao-consulta") do |xml|
        xml.tag!("dados-ec") do
          xml.numero Cielo.numero_afiliacao
          xml.chave Cielo.chave_acesso
        end
        xml.tid "#{cielo_tid}"
      end
      make_request! message
    end

    # captura uma transação que já esteja autorizada
    def catch!(cielo_tid)
      return nil unless cielo_tid
      message = xml_builder("requisicao-captura") do |xml|
				xml.tid "#{cielo_tid}"

        xml.tag!("dados-ec") do
          xml.numero Cielo.numero_afiliacao
          xml.chave Cielo.chave_acesso
        end
      end
      make_request! message
    end

    private

    # verifica os parametros para iniciar uma nova transação
    def create_parameters(parameters={})
      [:numero, :valor, :bandeira].each do |parameter|
        raise Cielo::MissingArgumentError, "Required parameter #{parameter} not found" unless parameters[parameter]
      end
      parameters.merge!(:moeda => "986") unless parameters[:moeda]
      parameters.merge!(:"data-hora" => Time.now.strftime("%Y-%m-%dT%H:%M:%S")) unless parameters[:"data-hora"]
      parameters.merge!(:idioma => "PT") unless parameters[:idioma]
      parameters.merge!(:produto => "1") unless parameters[:produto]
      parameters.merge!(:parcelas => "1") unless parameters[:parcelas]
      parameters.merge!(:autorizar => "2") unless parameters[:autorizar]
      parameters.merge!(:capturar => "true") unless parameters[:capturar]
      parameters.merge!(:"url-retorno" => Cielo.return_path) unless parameters[:"url-retorno"]
      parameters
    end

    # verifica os parametros para efetuar uma autorização direta
    def auth_parameters(parameters={})
      create_parameters(parameters)
      [:tid, :"cartao-numero", :"cartao-validade", :"cartao-codigo-seguranca", :"cartao-nome-portador"].each do |parameter|
        raise Cielo::MissingArgumentError, "Required parameter #{parameter} not found" unless parameters[parameter]
      end
      parameters.merge!(:"cartao-indicador" => "1") unless parameters[:"cartao-indicador"]
      parameters
    end

    # gera xml para as requisições ao webservice
    def xml_builder(group_name, &block)
      xml = Builder::XmlMarkup.new(:indent => 2)
      xml.instruct! :xml, :version => "1.0", :encoding => "ISO-8859-1"
      xml.tag!(group_name, :id => "#{Time.now.to_i}", :versao => "1.1.0") do
        #block.call(xml) if target == :before

        block.call(xml) # if target == :after
      end
      xml
    end

    # efetua requisição ao webservice
    def make_request!(message)
      #message.target!
      params = { :mensagem => message.target! }
      result = @connection.request! params
      parse_response(result)
    end

    # obtém o retorno do webservice em XML
    def parse_response(response)
      case response
      when Net::HTTPSuccess
        document = REXML::Document.new(response.body)
        parse_elements(document.elements)
      else
        {:erro => { :codigo => "000", :mensagem => "Impossível conectar ao servidor"}}
      end
    end

    # trata o retorno do webservice tranformando o XML em Hash
    def parse_elements(elements)
      map={}
      elements.each do |element|
        element_map = {}
        element_map = element.text if element.elements.empty? && element.attributes.empty?
        element_map.merge!("value" => element.text) if element.elements.empty? && !element.attributes.empty?
        element_map.merge!(parse_elements(element.elements)) unless element.elements.empty?
        map.merge!(element.name => element_map)
      end
      map.symbolize_keys
    end

  end
end