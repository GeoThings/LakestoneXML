//
//  XMLSerialization.swift
//  LakestoneXML
//
//  Created by Taras Vozniuk on 10/4/16.
//  Copyright © 2016 GeoThings. All rights reserved.
//
// --------------------------------------------------------
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import LakestoneCore

#if COOPER
	import java.io
	import javax.xml.parsers
	import lakestonecore.android
#else
	import LibXML2
	import Foundation
#endif

#if COOPER
	fileprivate typealias XMLNode = org.w3c.dom.Node
#else
	fileprivate typealias XMLNode = xmlNodePtr
#endif

/// Intermediate implementation of XML to Object serialization
/// libxml2 xmlNodePtr, xmlDocPtr and others should be properly wrapped later
public class XMLSerialization {
	
	public static var attributePrefix = "attribute::"
	public static var valueKey = "node::value"
	
	public class Error {
		static let UnsupportedEncoding = LakestoneError.with(stringRepresentation: "Data is not UTF8 encoded. (Other encodings are not yet supported)")
		static let ObjectIsNotSerializable = LakestoneError.with(stringRepresentation: "Object is not serializable")
		static let RootNodeRetrivalFailure = LakestoneError.with(stringRepresentation: "Root node retrieval failure")
	}
	
	private static var needsValueToBasetypeConversion: Bool = false
	public class func xmlObject(with data: Data, withValueToBasetypeConversion: Bool = false) throws -> [String: Any] {
		
		self.needsValueToBasetypeConversion = withValueToBasetypeConversion
		guard let stringRepresentation = data.utf8EncodedStringRepresentationº else {
			throw Error.UnsupportedEncoding
		}
		
		#if COOPER
		
			let documentBuilder = DocumentBuilderFactory.newInstance().newDocumentBuilder()
			data.position(0)
			let document = documentBuilder.parse(ByteArrayInputStream(data.plainBytes))
			
			guard let documentNode = document.getDocumentElement() else {
				throw Error.RootNodeRetrivalFailure
			}
			
		#else
		
			xmlInitParser()
			xmlXPathInit()
			
			guard let documentPtr = xmlReadDoc(stringRepresentation, "noname.xml", nil, Int32(XML_PARSE_NOBLANKS.rawValue)) else {
				throw Error.ObjectIsNotSerializable
			}
			
			// this thing should be thread-safe, but I am not completely sure
			if xmlGetLastError() != nil {
				xmlResetLastError()
				throw Error.ObjectIsNotSerializable
			}
			
			guard let documentNode = xmlDocGetRootElement(documentPtr) else {
				throw Error.RootNodeRetrivalFailure
			}
			
			defer {
				xmlFreeDoc(documentPtr)
			}
		
		#endif
		
		guard let rootNodeName = _name(forNode: documentNode),
			  let serializedNode = _serialize(node: documentNode)
		else {
			throw Error.RootNodeRetrivalFailure
		}
		
		return [rootNodeName: serializedNode]
	}
	
	private class func _traverse(node: XMLNode) -> [String: Any]? {
		
		var targetDictionary = [String: Any]()
		var childEntities = [String: [Any]]()
		
		#if COOPER
		
			let nodeList = node.getChildNodes()
			for index in 0 ..< nodeList.getLength(){
				
				let child = nodeList.item(index)
				guard _isElement(node: child) else {
					continue
				}
				guard let childName = _name(forNode: child) else {
					continue
				}
				
				var nameAssociatedList = childEntities[childName] ?? [Any]()
				if let serializedChild = _serialize(node: child){
					nameAssociatedList.append(serializedChild)
					childEntities[childName] = nameAssociatedList
				}
			}
			
		#else
			
			var childPtrº = node.pointee.children
			while let child = childPtrº {
				defer {
					childPtrº = childPtrº?.pointee.next
				}
				
				guard _isElement(node: child) else {
					continue
				}
				guard let childName = _name(forNode: child) else {
					continue
				}
				
				var nameAssociatedList = childEntities[childName] ?? [Any]()
				if let serializedChild = _serialize(node: child){
					nameAssociatedList.append(serializedChild)
					childEntities[childName] = nameAssociatedList
				}
			}
		
		#endif
		
		for (childName, nameAssociatedEntities) in childEntities {
			if nameAssociatedEntities.isEmpty {
				continue
			} else if let entity = nameAssociatedEntities.first, nameAssociatedEntities.count == 1 {
				targetDictionary[childName] = entity
			} else if nameAssociatedEntities.count > 1 {
				targetDictionary[childName] = nameAssociatedEntities
			}
		}
		
		return (targetDictionary.isEmpty) ? nil : targetDictionary
	}
	
	private class func _serialize(node: XMLNode) -> Any? {
		
		guard let rootNodeAttributes = _attributes(forNode: node)
		else {
			return nil
		}
		
		var targetDictionary = [String: Any]()
		for (attributeKey, attributeValue) in rootNodeAttributes {
			targetDictionary["\(self.attributePrefix)\(attributeKey)"] = attributeValue
		}
		
		if let serializedChildren = _traverse(node: node) {
			for (childName, childValue) in serializedChildren {
				targetDictionary[childName] = childValue
			}
		}
		
		if let value = _value(forNode: node){
			
			//node is value only, interpret this node as concrete non-collection type
			if targetDictionary.isEmpty {
				return value
			} else if let stringValue = value as? String {
				if !stringValue.isEmpty {
					targetDictionary[self.valueKey] = value
				}
			} else {
				targetDictionary[self.valueKey] = value
			}
		}

		return targetDictionary
	}

	private class func _name(forNode node: XMLNode) -> String? {
	
		#if COOPER
			return node.getNodeName()
		
		#else
		
			guard let targetName = node.pointee.name else {
				return nil
			}
			
			return String(validatingUTF8: UnsafeRawPointer(targetName).assumingMemoryBound(to: CChar.self))
		
		#endif
	}
	
	private class func _attributes(forNode node: XMLNode) -> [String: Any]? {
		
		var targetAttributes = [String: Any]()
		guard _isElement(node: node) else {
			return nil
		}
		
		#if COOPER

			let attributesMap = node.getAttributes()
			for attributeIndex in 0 ..< attributesMap.getLength() {
				let attributeItem = attributesMap.item(attributeIndex)
				if let attributeValue = attributeItem.getNodeValue() {
					targetAttributes[attributeItem.getNodeName()] = _attemptBaseTypeConversion(for: attributeValue)
				}
			}
		
		#else
			
			var attributePtrº = node.pointee.properties
			while let attribute = attributePtrº {
				
				defer {
					attributePtrº = attribute.pointee.next
				}
				
				guard let attributeNamePtr = attribute.pointee.name,
					let attributeName = String(validatingUTF8: UnsafeRawPointer(attributeNamePtr).assumingMemoryBound(to: CChar.self))
					else {
						print("\(#file): Attribute name retrival failed.")
						continue
				}
				
				guard let attributeValuePtr = xmlGetProp(node, attributeNamePtr),
					let attributeValue = String(validatingUTF8: UnsafeRawPointer(attributeValuePtr).assumingMemoryBound(to: CChar.self))
					else {
						print("\(#file): Attribute value retrival failed.")
						continue
				}
				
				defer {
					xmlFree(attributeValuePtr)
				}
				
				targetAttributes[attributeName] = _attemptBaseTypeConversion(for: attributeValue)
			}
		
		#endif
		
		return targetAttributes
	}
	
	private class func _isElement(node: XMLNode) -> Bool {
		
		#if COOPER
			return (node.getNodeType() == XMLNode.ELEMENT_NODE)
			
		#else
			return (node.pointee.type == XML_ELEMENT_NODE)
			
		#endif
	}
	
	private class func _value(forNode node: XMLNode) -> Any? {
		
		#if COOPER
			if let nodeValue = node.getNodeValue(){
				return _attemptBaseTypeConversion(for: node.getNodeValue())
			} else {
				return nil
			}
			
		#else
		
			guard let nodeContentPtr = xmlNodeGetContent(node),
				let nodeContent = String(validatingUTF8: UnsafeRawPointer(nodeContentPtr).assumingMemoryBound(to: CChar.self))
				else {
					return nil
			}
			
			defer {
				xmlFree(nodeContentPtr)
			}
			
			return _attemptBaseTypeConversion(for: nodeContent)
		
		#endif
	}
	
	private class func _attemptBaseTypeConversion(for stringEntity: String) -> Any {
		
		if !self.needsValueToBasetypeConversion {
			return stringEntity
		}
		
		#if COOPER
			let cleanedStringEntity = stringEntity.replaceAll("\n", "").replaceAll("\n", "")
		#else
			let cleanedStringEntity = stringEntity.replacingOccurrences(of: "\n", with: String()).replacingOccurrences(of: " ", with: "")
		#endif
		
		if let boolRepresentation = cleanedStringEntity.boolRepresentation {
			return boolRepresentation
		} else if let longRepresentation = cleanedStringEntity.longDecimalRepresentation {
			return longRepresentation
		} else if let doubleRepresentation = cleanedStringEntity.doubleRepresentation {
			return doubleRepresentation
		} else {
			return stringEntity
		}
	}
}
