/*
Copyright 2023.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package v1alpha1

type EntityConfiguration struct {
	// Type specifies the type of entity
	// +kubebuilder:validation:Enum=application;databaseServer;virtualMachine
	Type string `json:"type"`

	// HostedOnVM specifies if an entity is hosted on VM
	// If not set, the entity is assumed to be hosted on a container
	HostedOnVM    bool                  `json:"hostedOnVM,omitempty"`
	MetricConfigs []MetricConfiguration `json:"metrics"`

	// AttributeConfigs specifies how to map labels into attributes of an entity
	// +listType=map
	// +listMapKey=name
	// +kubebuilder:validation:MinItems=1
	AttributeConfigs []AttributeConfiguration `json:"attributes"`
}

type AttributeConfiguration struct {
	// The name of the attribute
	Name string `json:"name"`

	// The name of the label
	// If the Matches field is not specified, the value of this label will be used as the
	// attribute value
	Label string `json:"label"`

	// Matches specifies the regular expression to extract the pattern from the label value
	// and then use it as the attribute value
	// +optional
	Matches string `json:"matches,omitempty"`

	// As specifies how to reconstruct the extracted patterns from the result of the Matches
	// and use that as the attribute value instead
	// This field is only evaluated when Matches field is specified
	// +optional
	As string `json:"as,omitempty"`

	// IsIdentifier specifies if this attribute should be used as the identifier of an entity
	// There should be one and only one identifier for an entity
	// +optional
	IsIdentifier bool `json:"isIdentifier,omitempty"`
}

type EntityStatus struct {
	Type  string `json:"type"`
	Count *int32 `json:"count"`
}
