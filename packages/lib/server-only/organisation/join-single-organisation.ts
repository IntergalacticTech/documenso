import { prisma } from '@documenso/prisma';
import type { Organisation, OrganisationGroup } from '@prisma/client';
import { OrganisationMemberRole, OrganisationType } from '@prisma/client';

import { SINGLE_ORGANISATION_NAME, SINGLE_ORGANISATION_URL } from '../../constants/app';
import { AppError, AppErrorCode } from '../../errors/app-error';
import { INTERNAL_CLAIM_ID } from '../../types/subscription';
import { getSubscriptionClaim } from '../subscription/get-subscription-claim';
import { createTeam } from '../team/create-team';
import { addUserToOrganisation } from './accept-organisation-invitation';
import { createOrganisation } from './create-organisation';

/**
 * Puts a new user into the instance's single organisation. The first user to
 * arrive creates it and becomes its owner; everyone after joins as a member.
 */
export const joinSingleOrganisation = async ({ userId }: { userId: number }) => {
  const url = SINGLE_ORGANISATION_URL();

  if (!url) {
    return;
  }

  const existingOrganisation = await findSingleOrganisation(url);

  if (existingOrganisation) {
    await addMember(userId, existingOrganisation);

    return;
  }

  const freeSubscriptionClaim = await getSubscriptionClaim(INTERNAL_CLAIM_ID.FREE);

  const organisation = await createOrganisation({
    name: SINGLE_ORGANISATION_NAME(),
    url,
    type: OrganisationType.ORGANISATION,
    userId,
    claim: freeSubscriptionClaim,
  }).catch(() => null);

  // Two first-ever sign-ins can race on the unique url; the loser joins the winner's organisation.
  if (!organisation) {
    const racedOrganisation = await findSingleOrganisation(url);

    if (!racedOrganisation) {
      throw new AppError(AppErrorCode.UNKNOWN_ERROR, {
        message: 'Failed to create the single organisation',
      });
    }

    await addMember(userId, racedOrganisation);

    return;
  }

  await createTeam({
    userId,
    teamName: SINGLE_ORGANISATION_NAME(),
    teamUrl: url,
    organisationId: organisation.id,
    inheritMembers: true,
  });
};

const findSingleOrganisation = async (url: string) => {
  return await prisma.organisation.findUnique({
    where: { url },
    include: { groups: true },
  });
};

const addMember = async (userId: number, organisation: Organisation & { groups: OrganisationGroup[] }) => {
  await addUserToOrganisation({
    userId,
    organisationId: organisation.id,
    organisationGroups: organisation.groups,
    organisationMemberRole: OrganisationMemberRole.MEMBER,
  });
};
