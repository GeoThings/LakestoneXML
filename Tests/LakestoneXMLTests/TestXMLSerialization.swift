//
//  TestXMLSerialization.swift
//  LakestoneXML
//
//  Created by Taras Vozniuk on 10/5/16.
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


#if COOPER
	
	import remobjects.elements.eunit
	import lakestonecore.android
	
#else
	
	import XCTest
	import Foundation
	import LakestoneCore
	
	@testable import LakestoneXML
	
#endif

class TestXMLSerialization: Test {
	
	var xmlData: Data!
	
	#if COOPER
	override func Setup(){
		super.Setup()
		self.commonSetup()
	}
	#else
	override func setUp() {
		super.setUp()
		self.commonSetup()
	}
	#endif

	func commonSetup() {
		
		#if COOPER
		
			let xmlResourceStream = MainActivity.currentInstance.getResources().openRawResource(R.raw.osm_changeset_sample)
			guard let xmlData = try? Data.from(inputStream: xmlResourceStream) else {
				Assert.Fail("Cannot interpret the raw resource as string")
				return
			}
			
			self.xmlData = xmlData

		#elseif os(iOS) || os(watchOS) || os(tvOS)
		
			guard let resourcePath = Bundle(for: type(of: self)).path(forResource: "osmChangesetSample", ofType: "xml") else {
				XCTFail("Cannot find desired resource in current bundle")
				return
			}
			
			guard let xmlData = try? Data(contentsOf: URL(fileURLWithPath: resourcePath)) else {
				XCTFail("Cannot read from reasouce path: \(resourcePath)")
				return
			}
			
			self.xmlData = xmlData
			
		#else
		
			guard let sampleChangesetFileURL = URL(string: "http://api.openstreetmap.org/api/0.6/changeset/4012500/download") else {
				Assert.Fail("Remote resource URL has invalid format")
				return
			}
			
			let request = HTTP.Request(url: sampleChangesetFileURL)
			var response: HTTP.Response
			do {
				response = try request.performSync()
			} catch {
				Assert.Fail("\(error)")
				return
			}
			
			guard let responseData = response.dataº else {
				Assert.Fail("Response data is nil while expected")
				return
			}
			
			self.xmlData = responseData
			
		#endif
	}
	
	public func testXMLSerialization(){
		
		let xmlObject: [String: Any]
		do {
			xmlObject = try XMLSerialization.xmlObject(with: self.xmlData)
		} catch {
			Assert.Fail("XML Serialization failed: \(error)")
			return
		}
		
		Assert.AreEqual(xmlObject.keys.first ?? "", "osmChange")
		guard let osmChangeDict = xmlObject["osmChange"] as? [String: Any] else {
			Assert.Fail("Serialized XML doesn't contain osmChange object")
			return
		}
		
		Assert.AreEqual(osmChangeDict.keys.count, 8)
		Assert.AreEqual((osmChangeDict["modify"] as? [Any])?.count ?? 0, 49)
		Assert.AreEqual((osmChangeDict["create"] as? [Any])?.count ?? 0, 16)
		Assert.AreEqual((osmChangeDict["delete"] as? [Any])?.count ?? 0, 17)
		
		
		guard let createdEntity = ((osmChangeDict["create"] as? [Any])?.first as? [String: Any])?["node"] as? [String: Any] else {
			Assert.Fail("Cannot retrieve the first created eleement")
			return
		}
		
		Assert.AreEqual((createdEntity[XMLSerialization.attributePrefix + "uid"] as? String) ?? "", "161619")
		Assert.AreEqual((createdEntity[XMLSerialization.attributePrefix + "id"] as? String) ?? "", "658837513")
		Assert.AreEqual((createdEntity[XMLSerialization.attributePrefix + "timestamp"] as? String) ?? "", "2010-03-01T21:12:22Z")
		
		guard let modifiedWayEntity = ((osmChangeDict["modify"] as? [Any])?.last as? [String: Any])?["way"] as? [String: Any] else {
			Assert.Fail("Cannot retrieve the first created eleement")
			return
		}
		
		Assert.AreEqual((modifiedWayEntity["tag"] as? [String:Any])?[XMLSerialization.attributePrefix + "k"] as? String ?? "", "natural")
		Assert.AreEqual((modifiedWayEntity["tag"] as? [String:Any])?[XMLSerialization.attributePrefix + "v"] as? String ?? "", "scrub")
	}
	
}

#if !COOPER

extension TestXMLSerialization {
	static var allTests : [(String, (TestXMLSerialization) -> () throws -> Void)] {
		return [
			("testXMLSerialization", testXMLSerialization)
		]
	}
}

#endif
