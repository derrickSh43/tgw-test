variable "regions" {
  default = ["new_york"]
}

variable "hub_region" {
  default = "tokyo"
}
#############################################################
# TRANSIT GATEWAY
#############################################################
resource "aws_ec2_transit_gateway" "local" {
#    for_each = toset(var.regions)
provider = aws.new_york
  description = "new_york"
  auto_accept_shared_attachments = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support = "enable"
  tags = {
    Name = "new_york TGW"
  }
}
//Remove when not testing
resource "aws_ec2_transit_gateway" "peer" {
   provider = aws.tokyo
  description = "tokyo"
  auto_accept_shared_attachments = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support = "enable"
  tags = {
    Name = "tokyo TGW"
  }
}
#############################################################
# TRANSIT GATEWAY VPC ATTACHMENT
#############################################################
resource "aws_ec2_transit_gateway_vpc_attachment" "local_attachment" {
  #for_each = toset(var.regions) 
  provider = aws.new_york
  subnet_ids         = aws_subnet.private_subnet_new_york[*].id
  transit_gateway_id = aws_ec2_transit_gateway.local.id
  vpc_id             = aws_vpc.new_york.id
  dns_support        = "enable"
 
  tags = {
    Name = "Attachment for tokyo"
  }
}
//Remove when not testing
resource "aws_ec2_transit_gateway_vpc_attachment" "peer_attachment" {
     provider = aws.tokyo

  subnet_ids         = aws_subnet.private_subnet_tokyo[*].id
  transit_gateway_id = aws_ec2_transit_gateway.peer.id
  vpc_id             = aws_vpc.tokyo.id
  dns_support        = "enable"
  tags = {
    Name = "Attachment for tokyo"
  }
}

#############################################################
# TRANSIT GATEWAY PEERING ATTACHMENT
#############################################################
resource "aws_ec2_transit_gateway_peering_attachment" "hub_to_spoke" {
 # for_each = toset(var.regions)

  # Skip the hub region (e.g., "us-east-1")
  transit_gateway_id      = aws_ec2_transit_gateway.local.id # Hub TGW
  peer_transit_gateway_id = aws_ec2_transit_gateway.peer.id   # Spoke TGWs
  peer_region             = "ap-northeast-1"

  tags = {
    Name = "Hub to Spoke Peering new york"
  }

  provider = aws.new_york # Hub TGW provider
}
#############################################################
# TRANSIT GATEWAY PEERING ACCEPTER
#############################################################
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "spoke_accept" {
#  for_each = toset(var.regions)

  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke.id
  provider                      = aws.tokyo
  tags = {
    Name = "Spoke Accept Hub Peering tokyo"
  }
}
#############################################################
# TRANSIT GATEWAY ROURES HUB TO SPOKE
#############################################################
/*
resource "aws_ec2_transit_gateway_route" "hub_to_spoke_routes" {
  for_each = toset(var.regions)


  destination_cidr_block         = aws_vpc.[each.key].cidr_block                     # Spoke VPC CIDR
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke.id
  provider                       = aws.tokyo # Hub TGW provider
}
resource "aws_ec2_transit_gateway_route" "spoke_to_hub_routes" {
  #for_each = toset(var.regions)

  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.tgw_routes[each.key].id
  destination_cidr_block         = aws_vpc.regional_vpcs["tokyo"].cidr_block # Hub VPC CIDR
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.hub_to_spoke[each.key].id

}
resource "aws_route" "hub_vpc_to_spokes" {
  for_each = toset(var.regions)

  route_table_id         = aws_vpc_route_table.hub_route_table.id
  destination_cidr_block = aws_vpc.regional_vpcs[each.key].cidr_block # Spoke VPC CIDR
  transit_gateway_id     = aws_ec2_transit_gateway.local["tokyo"].id
}
*/